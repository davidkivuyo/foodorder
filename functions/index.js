/**
 * CampusBite Cloud Functions
 * ===========================
 *
 * Combined deployment of all CampusBite Cloud Functions:
 *
 * 1) processExpiredPickups — Scheduled (every 5 min) pickup-expiry processor:
 *    marks expired orders as no_show and notifies the student. The automatic
 *    strike engine has been removed; no strikes are issued.
 * 2) extendPickupDeadline — Callable (student) — extends an order's pickup
 *    deadline by 10 minutes, once per order, before the deadline passes.
 * 3) onOrderStatusChanged — Firestore trigger on orders/{orderId}.
 * 4) onNewOrder — Firestore trigger on orders/{orderId} (document created).
 * 5) onNewNotification — Firestore trigger on notifications/{notificationId} (FCM push).
 * 6) deleteCloudinaryImage — Callable function (admin only, secrets-protected).
 * 7) cleanupDeletedNotifications — Scheduled (every 24h) cleanup.
 * 8) cleanupInactiveTokens — Scheduled (weekly) cleanup of stale device tokens.
 * 9) onReviewChanged — Firestore trigger on reviews/{reviewId} — recalculates
 *    food item rating statistics when a review is created, updated, or deleted.
 * 10) migrateLegacyOrderFoodIds — Scheduled (every 5 min) one-time backfill of
 *    the denormalised `foodIds` array on legacy COLLECTED orders so they become
 *    reviewable; bounded batch, resumable via a persisted cursor, self-completing.
 * 10b) migrateLegacyOrderCafes — Scheduled (every 5 min) one-time backfill of
 *    the server-authoritative `cafes` array on legacy orders (any status) so
 *    per-cafe admin scoping covers historical orders; bounded batch, resumable
 *    via a persisted cursor, self-completing.
 * 11) auditReviewCreationRate — Scheduled (every 24h) review-rate guardrail.
 */

// ── Imports ────────────────────────────────────────────────────────────────

const crypto = require("node:crypto");
const functions = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentUpdated, onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

/**
 * Generate a unique claim ID for delivery claim ownership.
 * Used to prevent stale workers from finalizing or releasing claims
 * that have been reclaimed by a newer worker.
 * @return {string}
 */
function generateClaimId() {
  return crypto.randomUUID();
}

admin.initializeApp();

const db = admin.firestore();
const PICKUP_WINDOW_MINUTES = 20;

/**
 * Configurable grace period after pickupDeadline before automatic NO_SHOW.
 * Initial default: 5 minutes.
 */
const DEFAULT_PICKUP_GRACE_PERIOD_MINUTES = 5;

/**
 * Length of the student cancellation window after an order is placed.
 * The order's cancellationDeadline is createdAt + this many minutes.
 * Matches the customer app's OrderCancellationService.windowMinutes.
 */
const CANCELLATION_WINDOW_MINUTES = 2;

/**
 * Maximum number of recent eligible pickup outcomes retained in the
 * student's `pickupReliability.recentPickupHistory` (Phase B.2).
 */
const RECENT_PICKUP_WINDOW_SIZE = 10;

/**
 * How long a reliability event may stay deferred waiting for the student's
 * user document before the engine gives up EXPLICITLY and audibly
 * (reliabilitySkippedReason: 'MISSING_USER') instead of silently dropping
 * the event. 7 days is far beyond any legitimate account-restoration delay.
 */
const RELIABILITY_MISSING_USER_RETRY_MS = 7 * 24 * 60 * 60 * 1000;

// Sentinel returned by the reliability transaction when the user document
// does not exist, so the deferral (marker write + retriable throw) runs
// outside the transaction instead of aborting it.
const DEFER_RELIABILITY_EVENT = Symbol("deferReliabilityEvent");

/**
 * Lease duration for delivery claim records.
 *
 * When a claim is created with status 'pending' and a claimedAt timestamp,
 * the claim is considered active for this duration. If the function crashes
 * after claiming but before finalizing, the lease will expire and a
 * subsequent retry can reclaim the token transactionally.
 *
 * 120 seconds is more than sufficient for the FCM send + response processing
 * which typically completes in under 5 seconds.
 */
const CLAIM_LEASE_SECONDS = 120;

// ── Shared helpers ─────────────────────────────────────────────────────────

/**
 * Build a unique eventId for a notification to enable duplicate prevention.
 * @param {string} action — e.g. 'ORDER_READY', 'ORDER_NO_SHOW'
 * @param {string} orderId
 * @param {string} [suffix] — optional extra uniqueness
 * @return {string}
 */
function notificationEventId(action, orderId, suffix) {
  const parts = [action, orderId];
  if (suffix) parts.push(suffix);
  return parts.join("_");
}

/**
 * Whether a Firestore write was rejected because the target document already
 * exists (create() on an existing doc). The Admin SDK surfaces the gRPC
 * ALREADY_EXISTS status (numeric code 6); the string forms are accepted too
 * for robustness across SDK versions.
 * @param {*} err
 * @return {boolean}
 */
function isAlreadyExistsError(err) {
  if (!err) return false;
  return (
    err.code === 6 ||
    String(err.code) === "6" ||
    err.code === "ALREADY_EXISTS" ||
    err.code === "already-exists"
  );
}

/**
 * Whether a Firestore operation failed because the target document no longer
 * exists (e.g. an order deleted mid-run). The Admin SDK surfaces the gRPC
 * NOT_FOUND status (numeric code 5); the string forms are accepted too for
 * robustness across SDK versions.
 * @param {*} err
 * @return {boolean}
 */
function isNotFoundError(err) {
  if (!err) return false;
  return (
    err.code === 5 ||
    String(err.code) === "5" ||
    err.code === "NOT_FOUND" ||
    err.code === "not-found"
  );
}

/**
 * Create a notification document in Firestore.
 * Skips creation if a notification with the same eventId already exists.
 *
 * Phase 8: FCM push delivery is handled by the onNewNotification trigger,
 * NOT by this function. This function only writes to Firestore.
 *
 * @param {Object} params
 * @param {string} params.recipientId
 * @param {string} params.recipientRole
 * @param {string} params.type — NotificationType value
 * @param {string} params.title
 * @param {string} params.message
 * @param {string} [params.orderId]
 * @param {string} [params.eventId]
 * @param {string} [params.deepLink]
 * @param {Object} [params.metadata]
 * @param {string} [params.createdBy='system']
 * @return {Promise<string|null>} — notification ID or null
 * @throws {Error} on unexpected write/query failures. An ALREADY_EXISTS
 *   conflict (concurrent duplicate) is treated as a duplicate and returns
 *   null instead of throwing.
 */
async function createNotification({
  recipientId,
  recipientRole,
  type,
  title,
  message,
  orderId,
  eventId,
  deepLink,
  metadata,
  createdBy = "system",
}) {
  const payload = {
    recipientId,
    recipientRole,
    type,
    title,
    message,
    orderId: orderId || null,
    eventId: eventId || null,
    deepLink: deepLink || null,
    metadata: metadata || null,
    read: false,
    readAt: null,
    deleted: false,
    deletedAt: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy,
  };

  try {
    if (eventId) {
      // Duplicate prevention: skip creation if a notification with the same
      // eventId already exists (also catches legacy random-ID duplicates).
      const existing = await db
          .collection("notifications")
          .where("eventId", "==", eventId)
          .limit(1)
          .get();

      if (!existing.empty) {
        console.log("[createNotification] Skipping duplicate notification event");
        return null;
      }

      // Deterministic document ID derived from the eventId, so concurrent
      // deliveries of the same event target the same document. Sanitisation
      // is collision-free: notificationEventId() only ever produces
      // [A-Za-z0-9_-] characters (action + order ID + optional suffix), so
      // two distinct eventIds cannot map to the same doc ID.
      const docId = eventId.replace(/[^A-Za-z0-9_-]/g, "_");
      const ref = db.collection("notifications").doc(docId);
      // Atomic create: unlike set(), create() fails if the document already
      // exists, so a concurrent or redelivered event can never overwrite an
      // existing notification's state (e.g. read/deleted flags). If another
      // delivery won the race, Firestore rejects with ALREADY_EXISTS, which
      // the catch below treats as the duplicate this branch guards against.
      await ref.create(payload);
      console.log(`[createNotification] Created ${type} notification`);
      return ref.id;
    }

    const docRef = await db.collection("notifications").add(payload);
    console.log(`[createNotification] Created ${type} notification`);
    return docRef.id;
  } catch (err) {
    // A concurrent delivery created the deterministic doc first — this is
    // the duplicate the pre-check above is designed to catch, so report it
    // as skipped rather than an error.
    if (eventId && isAlreadyExistsError(err)) {
      console.log(
        "[createNotification] Skipping duplicate notification event (concurrent)"
      );
      return null;
    }
    // Any other failure is propagated so the caller (and Cloud Functions
    // event retries) can react — notification creation is best-effort and
    // every call site already handles thrown errors.
    console.error(`[createNotification] Error creating ${type}:`, err);
    throw err;
  }
}

/**
 * Retry an async function with bounded exponential backoff and jitter.
 *
 * Permanent failures (determined by [isPermanent]) are not retried.
 * Transient failures are retried up to [maxRetries] times.
 *
 * @param {Function} fn — async function to retry; receives attempt index (0-based)
 * @param {Object} [options]
 * @param {number} [options.maxRetries=3]
 * @param {number} [options.baseDelayMs=200]
 * @param {number} [options.maxDelayMs=4000]
 * @param {Function} [options.isPermanent] — returns true if error should NOT be retried
 * @return {Promise<*>}
 */
async function withRetry(fn, options = {}) {
  const maxRetries = options.maxRetries ?? 3;
  const baseDelayMs = options.baseDelayMs ?? 200;
  const maxDelayMs = options.maxDelayMs ?? 4000;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn(attempt);
    } catch (err) {
      // If this is a permanent error, don't retry — throw immediately
      if (options.isPermanent && options.isPermanent(err)) {
        throw err;
      }

      // If this is the last attempt, rethrow
      if (attempt >= maxRetries) {
        throw err;
      }

      // Bounded exponential backoff with jitter
      const delay = Math.min(baseDelayMs * Math.pow(2, attempt), maxDelayMs);
      const jitter = Math.random() * delay;

      console.warn(
        `[withRetry] Attempt ${attempt + 1}/${maxRetries} failed, ` +
        `retrying in ${Math.round(delay + jitter)}ms: ${err.message}`
      );

      await new Promise((resolve) => setTimeout(resolve, delay + jitter));
    }
  }
}

/**
 * Determine if an FCM error is permanent (token should be deactivated).
 * @param {Object} resp — a single sendEachForMulticast response item
 * @return {boolean}
 */
function isFcmPermanentError(resp) {
  if (!resp.error) return false;
  const code = resp.error.code || "";
  const msg = resp.error.message || "";
  return (
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-argument" ||
    code === "messaging/invalid-registration-token" ||
    code === "messaging/not-found" ||
    code === "messaging/unregistered" ||
    msg.includes("UNREGISTERED") ||
    msg.includes("NotRegistered") ||
    msg.includes("INVALID_ARGUMENT")
  );
}

/**
 * Deactivate an invalid token in Firestore (best-effort).
 * Retries transient Firestore write failures with bounded backoff.
 *
 * @param {string} docId — device_tokens document ID
 * @param {string} reason — deactivation reason string
 * @return {Promise<boolean>} true if deactivation succeeded (or was already done)
 */
async function deactivateTokenDoc(docId, reason) {
  return withRetry(
    async () => {
      await db.collection("device_tokens").doc(docId).update({
        active: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        deactivationReason: reason,
      });
      return true;
    },
    {
      maxRetries: 2,
      baseDelayMs: 100,
      maxDelayMs: 1000,
      isPermanent: (err) =>
        isNotFoundError(err) || // doc already deleted
        err.code === "PERMISSION_DENIED",
    },
  );
}

/**
 * Determine if a multicast-level error is permanent (not worth retrying).
 * @param {Error} err
 * @return {boolean}
 */
function isSendLevelPermanentError(err) {
  const msg = err.message || "";
  return (
    err.code === "messaging/invalid-argument" ||
    err.code === "messaging/third-party-auth-error" ||
    err.code === "messaging/sender-id-mismatch" ||
    msg.includes("no valid tokens") ||
    msg.includes("no tokens")
  );
}

/**
 * Atomically record or reclaim a per-device delivery attempt.
 *
 * Uses a Firestore transaction with a lease-based claim system:
 *
 * 1. **First claim** — If no record exists, creates one with status 'pending',
 *    a unique `claimId`, and a `claimedAt` server timestamp.
 * 2. **Already claimed (active lease)** — If a record exists with status
 *    'pending' and `claimedAt` is within [CLAIM_LEASE_SECONDS], returns
 *    `{claimed: false}` — the device is considered already in flight.
 * 3. **Lease expired** — If a record exists with status 'pending' but
 *    `claimedAt` is older than [CLAIM_LEASE_SECONDS], the lease is assumed
 *    stale (e.g. the claiming function crashed). The transaction reclaims
 *    it by updating `claimedAt` and generating a new `claimId`, then
 *    returns `{claimed: true, claimId}`.
 * 4. **Terminal states** — Records with status 'delivered' or 'failed'
 *    are never reclaimed; returns `{claimed: false}`.
 *
 * The `claimId` is a unique identifier for each claim instance. All subsequent
 * finalization and release operations require this `claimId` to match the
 * current record. This prevents a stale worker (from a previous lease period)
 * from modifying a claim that has been reclaimed by a newer worker.
 *
 * **Return value:**
 * - `{claimed: true, claimId: string}` — claim was created or reclaimed.
 * - `{claimed: false}` — record is terminal or within active lease.
 * - **throws** — unexpected Firestore transaction error — the caller should
 *   treat this as a retry-eligible failure.
 *
 * @param {string} eventId — notification event ID for dedup
 * @param {string} deviceDocId — device_tokens document ID
 * @return {Promise<{claimed: boolean, claimId?: string}>}
 * @throws {Error} on unexpected Firestore errors
 */
async function recordDelivery(eventId, deviceDocId) {
  const docId = `${eventId}_${deviceDocId}`;
  const ref = db.collection("delivery_records").doc(docId);

  try {
    return await db.runTransaction(async (transaction) => {
      const doc = await transaction.get(ref);

      if (!doc.exists) {
        // ── First claim — create the record ────────────────────────
        const claimId = generateClaimId();
        transaction.create(ref, {
          eventId: eventId,
          deviceDocId: deviceDocId,
          status: "pending",
          claimId: claimId,
          errorMessage: null,
          claimedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { claimed: true, claimId };
      }

      const data = doc.data();

      // ── Terminal states — never reclaimed ────────────────────────
      if (data.status === "delivered" || data.status === "failed") {
        return { claimed: false };
      }

      // ── Lease check — is the claim still valid? ──────────────────
      if (data.status === "pending" && data.claimedAt) {
        const now = admin.firestore.Timestamp.now();
        const claimedAt = data.claimedAt;
        const elapsedMs =
          (now.seconds - claimedAt.seconds) * 1000 +
          (now.nanoseconds - claimedAt.nanoseconds) / 1e6;

        if (elapsedMs < CLAIM_LEASE_SECONDS * 1000) {
          // Lease still active — another instance is handling this device.
          return { claimed: false };
        }

        // Lease expired — reclaim the token with a new claimId.
        console.warn(
          `[recordDelivery] Lease expired ` +
          `(${Math.round(elapsedMs / 1000)}s old) — reclaiming`
        );
      }

      // ── Lease expired or unknown status — reclaim ────────────────
      const claimId = generateClaimId();
      transaction.update(ref, {
        status: "pending",
        claimId: claimId,
        claimedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { claimed: true, claimId };
    });
  } catch (err) {
    console.warn(
      `[recordDelivery] Transaction error: ${err.message} — propagating`
    );
    throw err;
  }
}

/**
 * Build the FCM multicast message for a set of tokens.
 *
 * @param {Object} params — notification payload fields
 * @param {string} params.title
 * @param {string} params.body
 * @param {string} [params.deepLink]
 * @param {string} [params.notificationId]
 * @param {string} [params.type]
 * @param {string} [params.orderId]
 * @param {string} [params.eventId]
 * @param {Array<{token: string}>} tokenList
 * @return {Object} admin.messaging multicast message
 */
function buildMessage({ title, body, deepLink, notificationId, type, orderId, eventId }, tokenList) {
  return {
    tokens: tokenList.map((t) => t.token),
    notification: {
      title: title,
      body: body,
    },
    data: {
      notificationId: notificationId || "",
      type: type || "",
      orderId: orderId || "",
      deepLink: deepLink || "",
      eventId: eventId || "",
    },
    android: {
      priority: "high",
      notification: {
        priority: "high",
        defaultSound: true,
        defaultVibrateTimings: true,
      },
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
          contentAvailable: true,
        },
      },
      headers: {
        "apns-priority": "10",
      },
    },
    webpush: {
      notification: {
        title: title,
        body: body,
        icon: "/favicon.png",
      },
      fcmOptions: {
        link: deepLink || "/",
      },
    },
  };
}

/**
 * Query the recipient's active device tokens.
 *
 * @param {string} recipientId
 * @param {string} recipientRole
 * @return {Promise<Array<{token: string, docId: string}>|null>} null when no
 *   active tokens exist (caller short-circuits), otherwise the token list.
 */
async function fetchActiveTokens(recipientId, recipientRole) {
  const tokensSnapshot = await db
      .collection("device_tokens")
      .where("userId", "==", recipientId)
      .where("active", "==", true)
      .get();

  if (tokensSnapshot.empty) {
    console.log(
      `[sendPush] No active tokens for ${recipientRole} — skipping push`
    );
    return null;
  }
  return tokensSnapshot.docs.map((doc) => ({
    token: doc.data().token,
    docId: doc.id,
  }));
}

/**
 * Lease-claim each remaining token for the current retry attempt.
 *
 * With an eventId each token is claimed transactionally via recordDelivery()
 * so that idempotent delivery holds across retries. Without an eventId every
 * remaining token is claimable (no dedup possible).
 *
 * @param {string} [eventId]
 * @param {Array<{token: string, docId: string}>} remainingTokens
 * @return {Promise<{claimedTokens: Array, claimErrors: Array, skippedCount: number}>}
 */
async function claimTokensForAttempt(eventId, remainingTokens) {
  const claimedTokens = [];
  const claimErrors = [];
  if (!eventId) {
    claimedTokens.push(...remainingTokens);
    return { claimedTokens, claimErrors, skippedCount: 0 };
  }

  const claimPromises = [];
  for (const t of remainingTokens) {
    // recordDelivery:
    //   returns true  → first claim (send this round)
    //   returns false → already claimed (skip)
    //   throws        → unexpected error (retry next iteration)
    const p = recordDelivery(eventId, t.docId)
      .then((result) => {
        // result: {claimed: true, claimId} or {claimed: false}
        if (result.claimed) {
          // Attach the claimId to the token entry so
          // finalizeDelivery and releaseDeliveryClaim can
          // verify ownership.
          claimedTokens.push({
            token: t.token,
            docId: t.docId,
            claimId: result.claimId,
          });
        }
      })
      .catch((err) => {
        claimErrors.push(t);
        console.warn(
          `[sendPush] Claim failed: ` +
          `${err.message} — will retry`
        );
      });
    claimPromises.push(p);
  }
  await Promise.allSettled(claimPromises);

  const skippedCount =
    claimPromises.length - claimedTokens.length - claimErrors.length;
  return { claimedTokens, claimErrors, skippedCount };
}

/**
 * Send the multicast with bounded retry for send-level transient errors.
 *
 * @param {Object} message
 * @return {Promise<Object>} admin.messaging multicast response
 */
async function sendMulticast(message) {
  return withRetry(
    async () => {
      return await admin.messaging().sendEachForMulticast(message);
    },
    {
      maxRetries: 1,
      baseDelayMs: 400,
      maxDelayMs: 2000,
      isPermanent: isSendLevelPermanentError,
    },
  );
}

/**
 * Classify every per-token FCM response into delivered, permanently failed,
 * or transiently failed buckets, building the finalization/deactivation work.
 *
 * @param {Object} ctx
 * @param {Object} ctx.response — admin.messaging multicast response
 * @param {Array} ctx.claimedTokens — token entries sent in this attempt
 * @param {string} [ctx.eventId]
 * @param {number} ctx.retryAttempt
 * @param {number} ctx.maxFcmRetries
 * @param {Array} ctx.failures — shared failures accumulator (mutated)
 * @return {Object} bucketed results for the caller
 */
/**
 * Classify a single per-token FCM response into the relevant buckets.
 *
 * @param {Object} resp — one element of the multicast response array
 * @param {Object} tokenEntry — the claimed token this response belongs to
 * @param {Object} ctx
 * @param {string} [ctx.eventId]
 * @param {number} ctx.retryAttempt
 * @param {number} ctx.maxFcmRetries
 * @param {Array} ctx.failures — shared failures accumulator (mutated)
 * @param {Array} ctx.finalizePromises — finalization work (mutated)
 * @param {Array} ctx.tokensToDeactivate — deactivation work (mutated)
 * @param {Array} ctx.tokensToRelease — release work (mutated)
 * @return {number} 1 when the token was delivered this round, 0 otherwise
 */
function classifyResponse(resp, tokenEntry, ctx) {
  if (resp.success) {
    if (ctx.eventId) {
      ctx.finalizePromises.push(
        finalizeDelivery(ctx.eventId, tokenEntry.docId, "delivered", null, tokenEntry.claimId)
      );
    }
    return 1;
  }

  if (isFcmPermanentError(resp)) {
    const reason =
      (resp.error && (resp.error.code || resp.error.message)) || "permanent_failure";
    if (ctx.eventId) {
      ctx.finalizePromises.push(
        finalizeDelivery(ctx.eventId, tokenEntry.docId, "failed", reason, tokenEntry.claimId)
      );
    }
    ctx.tokensToDeactivate.push({ docId: tokenEntry.docId, reason });
    ctx.failures.push({
      tokenDocId: tokenEntry.docId,
      error: reason,
      transient: false,
    });
    return 0;
  }

  const errorMsg =
    (resp.error && (resp.error.code || resp.error.message)) || "transient_failure";
  if (ctx.retryAttempt < ctx.maxFcmRetries) {
    ctx.tokensToRelease.push({ tokenEntry, errorMsg });
  } else {
    if (ctx.eventId) {
      ctx.finalizePromises.push(
        finalizeDelivery(ctx.eventId, tokenEntry.docId, "failed", errorMsg, tokenEntry.claimId)
      );
    }
    ctx.failures.push({
      tokenDocId: tokenEntry.docId,
      error: errorMsg,
      transient: true,
    });
  }
  return 0;
}

function processFcmResponses({ response, claimedTokens, eventId, retryAttempt, maxFcmRetries, failures }) {
  const tokensToRetry = [];
  const tokensToDeactivate = [];
  const tokensToRelease = [];
  const finalizePromises = [];
  const ctx = { eventId, retryAttempt, maxFcmRetries, failures, finalizePromises, tokensToDeactivate, tokensToRelease };
  let newlySent = 0;

  for (let i = 0; i < response.responses.length; i++) {
    newlySent += classifyResponse(response.responses[i], claimedTokens[i], ctx);
  }

  return { newlySent, tokensToRetry, tokensToDeactivate, tokensToRelease, finalizePromises };
}

/**
 * Release pending claims for transient FCM failures so the next retry can
 * reclaim the token, or (without eventId) queue them directly for retry.
 *
 * @param {Object} ctx
 * @param {Array} ctx.tokensToRelease
 * @param {string} [ctx.eventId]
 * @param {number} ctx.retryAttempt
 * @param {number} ctx.maxFcmRetries
 * @param {Array} ctx.failures — shared failures accumulator (mutated)
 * @return {Promise<Array>} token entries to retry on the next attempt
 */
async function releasePendingClaims({ tokensToRelease, eventId, retryAttempt, maxFcmRetries, failures }) {
  const tokensToRetry = [];
  if (tokensToRelease.length === 0) return tokensToRetry;

  if (eventId) {
    const releaseResults = await Promise.allSettled(
      tokensToRelease.map(async ({ tokenEntry, errorMsg }) => {
        const released = await releaseDeliveryClaim(eventId, tokenEntry.docId, tokenEntry.claimId);
        return { tokenEntry, errorMsg, released };
      }),
    );

    for (const result of releaseResults) {
      applyReleaseResult(result, { retryAttempt, maxFcmRetries, failures }, tokensToRetry);
    }
  } else {
    for (const { tokenEntry, errorMsg } of tokensToRelease) {
      tokensToRetry.push(tokenEntry);
      console.warn(
        `[sendPush] Transient failure, ` +
        `will retry (attempt ${retryAttempt + 1}/${maxFcmRetries}): ${errorMsg}`
      );
    }
  }
  return tokensToRetry;
}

/**
 * Apply a single releaseDeliveryClaim outcome to the retry queue or failures.
 *
 * @param {PromiseRejectedResult|PromiseFulfilledResult} result
 * @param {Object} ctx
 * @param {number} ctx.retryAttempt
 * @param {number} ctx.maxFcmRetries
 * @param {Array} ctx.failures — shared failures accumulator (mutated)
 * @param {Array} tokensToRetry — retry queue for the next attempt (mutated)
 */
function applyReleaseResult(result, { retryAttempt, maxFcmRetries, failures }, tokensToRetry) {
  if (result.status === "rejected") {
    console.warn(
      `[sendPush] releaseDeliveryClaim rejected: ${result.reason?.message || "unknown error"}`
    );
    return;
  }

  const { tokenEntry, errorMsg, released } = result.value;
  if (released) {
    tokensToRetry.push(tokenEntry);
    console.warn(
      `[sendPush] Transient failure, ` +
      `will retry (attempt ${retryAttempt + 1}/${maxFcmRetries}): ${errorMsg}`
    );
  } else {
    // Claim could not be released (persistent Firestore error or
    // all retries exhausted).  Do NOT terminalize the token:
    // the pending claim with its lease remains in Firestore.
    // The lease will expire after CLAIM_LEASE_SECONDS (120s),
    // and the next function invocation will reclaim it via
    // recordDelivery().
    failures.push({
      tokenDocId: tokenEntry.docId,
      error: errorMsg,
      transient: true,
    });
    console.warn(
      `[sendPush] Could not release claim — ` +
      `pending claim preserved for lease-based recovery: ${errorMsg}`
    );
  }
}

/**
 * Deactivate permanently invalid tokens (best-effort).
 *
 * @param {Array<{docId: string, reason: string}>} tokensToDeactivate
 * @return {Promise<void>}
 */
async function deactivateInvalidTokens(tokensToDeactivate) {
  if (tokensToDeactivate.length === 0) return;

  console.log(`[sendPush] Deactivating ${tokensToDeactivate.length} permanently invalid token(s)`);
  const deactivateResults = await Promise.allSettled(
    tokensToDeactivate.map(({ docId, reason }) =>
      deactivateTokenDoc(docId, reason).catch((err) => {
        console.error(`[sendPush] Failed to deactivate a permanently invalid token after retries: ${err.message}`);
        return false;
      })
    ),
  );
  for (let i = 0; i < deactivateResults.length; i++) {
    if (deactivateResults[i].status === "rejected" || deactivateResults[i].value === false) {
      console.warn(`[sendPush] Could not deactivate a permanently invalid token — will be cleaned up by weekly scheduler`);
    }
  }
}


/**
 * Send an FCM push notification to all active devices belonging to a recipient.
 *
 * Queries the device_tokens collection for the recipient's active tokens
 * and sends a multicast message. Invalid tokens are deactivated.
 *
 * Transient token-level FCM errors are retried with bounded exponential
 * backoff with jitter. Transient device_tokens update errors are also
 * retried. Permanent failures (UNREGISTERED, NOT_FOUND, etc.) are never
 * retried; the token is deactivated immediately.
 *
 * Per-device/event idempotency:
 *   Before each retry, tokens that already have a successful `delivery_records`
 *   entry for this event are skipped — they were already delivered on a
 *   previous attempt even though FCM did not acknowledge it.
 *
 * @param {Object} params
 * @param {string} params.recipientId — the user to send the push to
 * @param {string} params.recipientRole — 'student' or 'admin'
 * @param {string} params.title — notification title
 * @param {string} params.body — notification body text
 * @param {string} [params.deepLink] — deep link for notification tap navigation
 * @param {string} [params.notificationId] — Firestore notification doc ID
 * @param {string} [params.type] — notification type (e.g. 'ORDER_READY')
 * @param {string} [params.orderId] — optional order ID
 * @param {string} [params.eventId] — optional event ID for dedup
 * @return {Promise<Object>} delivery results
 */

/**
 * Send one claimed batch: build the message, multicast with retry, classify
 * responses, release transient claims and deactivate invalid tokens.
 *
 * @param {Object} ctx
 * @param {string} ctx.title
 * @param {string} ctx.body
 * @param {string} [ctx.deepLink]
 * @param {string} [ctx.notificationId]
 * @param {string} [ctx.type]
 * @param {string} [ctx.orderId]
 * @param {string} [ctx.eventId]
 * @param {Array} ctx.claimedTokens
 * @param {number} ctx.retryAttempt
 * @param {number} ctx.maxFcmRetries
 * @param {Array} ctx.failures — shared failures accumulator (mutated)
 * @return {Promise<{newlySent: number, tokensToRetry: Array}|null>} null when
 *   the multicast failed after all send-level retries (caller aborts).
 */
async function sendClaimedBatch({
  title,
  body,
  deepLink,
  notificationId,
  type,
  orderId,
  eventId,
  claimedTokens,
  retryAttempt,
  maxFcmRetries,
  failures,
}) {
  const message = buildMessage(
    { title, body, deepLink, notificationId, type, orderId, eventId },
    claimedTokens,
  );

  let response;
  try {
    response = await sendMulticast(message);
  } catch (sendErr) {
    console.error(
      `[sendPush] Multicast send failed after retries: ${sendErr.message}`
    );
    const finalizePromises = claimedTokens.map((t) =>
      eventId
        ? finalizeDelivery(eventId, t.docId, "failed", sendErr.message, t.claimId)
        : Promise.resolve()
    );
    await Promise.allSettled(finalizePromises);
    for (const t of claimedTokens) {
      failures.push({
        tokenDocId: t.docId,
        error: sendErr.message,
        transient: true,
      });
    }
    return null;
  }

  const {
    newlySent,
    tokensToRetry,
    tokensToDeactivate,
    tokensToRelease,
    finalizePromises,
  } = processFcmResponses({
    response,
    claimedTokens,
    eventId,
    retryAttempt,
    maxFcmRetries,
    failures,
  });

  const releasedTokens = await releasePendingClaims({
    tokensToRelease,
    eventId,
    retryAttempt,
    maxFcmRetries,
    failures,
  });
  tokensToRetry.push(...releasedTokens);

  if (finalizePromises.length > 0) {
    await Promise.allSettled(finalizePromises);
  }

  await deactivateInvalidTokens(tokensToDeactivate);

  return { newlySent, tokensToRetry };
}

/**
 * Sleep with exponential backoff + jitter before the next retry, unless the
 * queue is empty or no retries remain.
 *
 * @param {number} remainingCount
 * @param {number} retryAttempt
 * @param {number} maxFcmRetries
 * @return {Promise<void>}
 */
async function backoffBeforeRetry(remainingCount, retryAttempt, maxFcmRetries) {
  if (remainingCount === 0 || retryAttempt >= maxFcmRetries) {
    return;
  }
  const delay = Math.min(200 * Math.pow(2, retryAttempt), 4000);
  const jitter = Math.random() * delay;
  console.log(
    `[sendPush] Retrying ${remainingCount} token(s) ` +
    `in ${Math.round(delay + jitter)}ms (attempt ${retryAttempt + 2}/${maxFcmRetries + 1})`
  );
  await new Promise((resolve) => setTimeout(resolve, delay + jitter));
}

async function sendPushNotification({
  recipientId,
  recipientRole,
  title,
  body,
  deepLink,
  notificationId,
  type,
  orderId,
  eventId,
}) {
  // These counters are updated across retries
  let sentCount = 0;
  let totalAttempted = 0;
  const failures = [];

  try {
    const activeTokens = await fetchActiveTokens(recipientId, recipientRole);
    if (activeTokens === null) {
      return { sent: 0, total: 0, failures: [] };
    }

    totalAttempted = activeTokens.length;

    console.log(
      `[sendPush] Sending push to ${activeTokens.length} device(s) for ${recipientRole}`
    );

    let remainingTokens = activeTokens;
    let retryAttempt = 0;
    const maxFcmRetries = 3;

    while (remainingTokens.length > 0 && retryAttempt <= maxFcmRetries) {
      const step = await runRetryIteration({
        title,
        body,
        deepLink,
        notificationId,
        type,
        orderId,
        eventId,
        remainingTokens,
        retryAttempt,
        maxFcmRetries,
        failures,
      });
      sentCount += step.sentCount;
      remainingTokens = step.remainingTokens;
      if (step.abort) {
        break;
      }
      retryAttempt++;
    }

    return {
      sent: sentCount,
      total: totalAttempted,
      failures: failures,
    };
  } catch (err) {
    console.error("[sendPush] Error sending push:", err);

    // The no-valid-tokens case at the send level is permanent
    if (isNoValidTokensError(err)) {
      return { sent: 0, total: 0, failures: [] };
    }

    return {
      sent: sentCount,
      total: totalAttempted || 0,
      failures: [{ error: err.message, transient: true }],
    };
  }
}

/**
 * Execute one retry iteration: claim tokens, send the batch, merge failures
 * and claim errors into the next round.
 *
 * @param {Object} ctx
 * @param {string} ctx.title
 * @param {string} ctx.body
 * @param {string} [ctx.deepLink]
 * @param {string} [ctx.notificationId]
 * @param {string} [ctx.type]
 * @param {string} [ctx.orderId]
 * @param {string} [ctx.eventId]
 * @param {Array} ctx.remainingTokens
 * @param {number} ctx.retryAttempt
 * @param {number} ctx.maxFcmRetries
 * @param {Array} ctx.failures — shared failures accumulator (mutated)
 * @return {Promise<{sentCount: number, remainingTokens: Array, abort: boolean}>}
 */
async function runRetryIteration({
  title,
  body,
  deepLink,
  notificationId,
  type,
  orderId,
  eventId,
  remainingTokens,
  retryAttempt,
  maxFcmRetries,
  failures,
}) {
  const { claimedTokens, claimErrors, skippedCount } =
    await claimTokensForAttempt(eventId, remainingTokens);

  if (skippedCount > 0) {
    console.log(
      `[sendPush] Skipped ${skippedCount} already-claimed device(s)`
    );
  }

  // Early exit: nothing to send and nothing to retry.
  if (claimedTokens.length === 0 && claimErrors.length === 0) {
    return { sentCount: 0, remainingTokens: [], abort: true };
  }

  const nextRemaining = [];
  let sentCount = 0;
  if (claimedTokens.length > 0) {
    const batch = await sendClaimedBatch({
      title,
      body,
      deepLink,
      notificationId,
      type,
      orderId,
      eventId,
      claimedTokens,
      retryAttempt,
      maxFcmRetries,
      failures,
    });
    if (batch === null) {
      return { sentCount: 0, remainingTokens: [], abort: true };
    }
    sentCount = batch.newlySent;
    nextRemaining.push(...batch.tokensToRetry);
  }

  // ── Merge claim errors into the next iteration ──────────────
  // claimErrors are tokens whose recordDelivery call threw (unexpected
  // Firestore error).  They were not sent this round and must be retried.
  // Merge them into remainingTokens so the next while-loop iteration
  // attempts them again.
  if (claimErrors.length > 0) {
    nextRemaining.push(...claimErrors);
  }

  await backoffBeforeRetry(nextRemaining.length, retryAttempt, maxFcmRetries);

  return { sentCount, remainingTokens: nextRemaining, abort: false };
}

/**
 * Detect the permanent send-level "no valid tokens" error.
 *
 * @param {Error} err
 * @return {boolean}
 */
function isNoValidTokensError(err) {
  return Boolean(
    err.message &&
    (err.message.includes("no valid tokens") ||
     err.message.includes("no tokens"))
  );
}

/**
 * Finalize a delivery record by updating its status from 'pending' to its
 * final outcome.
 *
 * Verifies [claimId] ownership before updating: if the current record's
 * claimId does not match the provided [claimId], the operation is skipped
 * (the claim was reclaimed by a newer worker).
 *
 * This is best-effort; failures (including claimId mismatch) are logged
 * but never block the push flow.
 *
 * @param {string} eventId
 * @param {string} deviceDocId
 * @param {'delivered'|'failed'} status
 * @param {string} [errorMessage]
 * @param {string} [claimId] — expected claimId for ownership verification
 * @return {Promise<void>}
 */
async function finalizeDelivery(eventId, deviceDocId, status, errorMessage, claimId) {
  const docId = `${eventId}_${deviceDocId}`;
  const ref = db.collection("delivery_records").doc(docId);
  try {
    // ── Ownership check: verify claimId matches ───────────────────
    if (claimId) {
      const doc = await ref.get();
      if (doc.exists && doc.data().claimId !== claimId) {
        // The claim was reclaimed by a newer worker.  This is expected
        // when the lease expired before finalization completed.
        console.warn(
          `[finalizeDelivery] claimId mismatch: ` +
          `expected ${claimId}, got ${doc.data().claimId} — skipping`
        );
        return;
      }
    }

    await ref.update({
      status: status,
      errorMessage: errorMessage || null,
      claimId: admin.firestore.FieldValue.delete(),
      claimedAt: admin.firestore.FieldValue.delete(),
    });
  } catch (err) {
    console.warn(
      `[finalizeDelivery] Error updating delivery record to ${status}: ${err.message}`
    );
  }
}

/**
 * Release a pending delivery claim by deleting its delivery_records document.
 *
 * Verifies [claimId] ownership before deleting: if the current record's
 * claimId does not match the provided [claimId], the deletion is skipped
 * (the claim was reclaimed by a newer worker — the lease expiration will
 * serve as recovery).
 *
 * Uses [withRetry] to retry transient Firestore delete failures with bounded
 * exponential backoff. Releasing the claim allows the next retry to reclaim
 * the token via `recordDelivery()` rather than waiting for the lease to
 * expire.
 *
 * Reads the document first: if it does not exist (already released), returns
 * true immediately without calling delete.  Transient delete failures are
 * retried.  PERMISSION_DENIED and claimId mismatch are never retried.
 *
 * @param {string} eventId
 * @param {string} deviceDocId
 * @param {string} [claimId] — expected claimId for ownership verification
 * @return {Promise<boolean>} true if the claim was released, false otherwise
 */
async function releaseDeliveryClaim(eventId, deviceDocId, claimId) {
  const docId = `${eventId}_${deviceDocId}`;
  const ref = db.collection("delivery_records").doc(docId);

  try {
    // The callback only needs to throw on failure — it performs no
    // meaningful return. The boolean contract lives here: withRetry
    // resolving means the claim is released (or was already released /
    // reclaimed), and any failure throws out to the catch below.
    await withRetry(
      async () => {
        const doc = await ref.get();
        if (!doc.exists) {
          // Document already deleted — the claim is already released.
          return;
        }

        // ── Ownership check: verify claimId matches ───────────────
        if (claimId && doc.data().claimId !== claimId) {
          // The claim was reclaimed by a newer worker.  Treat it as
          // released: from the old worker's perspective the claim was
          // already released (the new worker now owns it).  This avoids
          // a redundant finalizeDelivery attempt from the caller.
          console.warn(
            `[releaseDeliveryClaim] claimId mismatch: ` +
            `expected ${claimId}, got ${doc.data().claimId} — ` +
            `claim already reclaimed, treating as released`
          );
          return;
        }

        await ref.delete();
      },
      {
        maxRetries: 2,
        baseDelayMs: 100,
        maxDelayMs: 1000,
        isPermanent: (err) =>
          err.code === "PERMISSION_DENIED",
      },
    );
    return true;
  } catch (err) {
    console.warn(
      `[releaseDeliveryClaim] Failed to release claim: ${err.message}`
    );
    return false;
  }
}
// ════════════════════════════════════════════════════════════════════════════

/**
 * Process a single expired order inside a Firestore transaction.
 *
 * The automatic strike engine has been removed: an expired pickup is only
 * marked as a no-show and the student is notified. No strike counter, account
 * status, or suspension state is touched — strike management remains an
 * admin-only concern (admin app).
 *
 * @param {admin.firestore.Transaction} transaction
 * @param {admin.firestore.DocumentSnapshot} orderSnapshot
 * @return {Promise<boolean>} true if the no-show was processed, false if skipped
 */
async function processExpiredOrder(transaction, orderSnapshot) {
  const orderRef = orderSnapshot.ref;
  const orderData = orderSnapshot.data();

  if (!orderData) return false;

  // ── Step 1: Verify order is still eligible ──────────────────────
  if (orderData.status !== "ready") return false;
  if (orderData.deadlineStatus !== "ACTIVE") return false;
  if (orderData.noShowProcessed === true) return false;
  // Re-verify inside the transaction using server-authoritative time:
  // noShowEligibleAt = pickupDeadline + DEFAULT_PICKUP_GRACE_PERIOD_MINUTES.
  // The transition is permitted ONLY when currentServerTime >= noShowEligibleAt.
  const pickupDeadline = orderData.pickupDeadline;
  if (!(pickupDeadline instanceof admin.firestore.Timestamp)) return false;
  const now = admin.firestore.Timestamp.now();
  const noShowEligibleAtMs =
    pickupDeadline.toMillis() + DEFAULT_PICKUP_GRACE_PERIOD_MINUTES * 60 * 1000;
  if (now.toMillis() < noShowEligibleAtMs) {
    return false;
  }

  const studentId = orderData.studentId;
  if (!studentId) {
    console.warn("[PickupExpiry] Order without studentId – skipping");
    return false;
  }

  // ── Step 2: Update order to no_show ─────────────────────────────
  transaction.update(orderRef, {
    status: "no_show",
    deadlineStatus: "EXPIRED",
    noShowProcessed: true,
    noShowAt: admin.firestore.FieldValue.serverTimestamp(),
    expiredAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    // Phase H — default food disposition when an order becomes NO_SHOW:
    // UNRESOLVED until an authorized admin records the actual outcome
    // (AGENTS.md §3). This is written on the terminal transition only, so
    // it can never overwrite a disposition an admin already recorded.
    foodDisposition: "UNRESOLVED",
  });

  // ── Step 3: Create audit log ────────────────────────────────────
  const auditRef = db.collection("audit_logs").doc();
  transaction.set(auditRef, {
    action: "automatic_no_show",
    orderId: orderSnapshot.id,
    studentId: studentId,
    performedBy: "system",
    reason: "pickup_deadline_expired",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(
    `[PickupExpiry] Order ${orderSnapshot.id} marked no_show ` +
    `(pickup deadline + grace period expired)`
  );

  return true;
}

/**
 * Reconcile deferred reliability events (reliabilityPending orders).
 *
 * Cloud Functions redelivers a failed trigger event only for a bounded
 * window, so a terminal event whose user document is missing must ALSO be
 * reconciled by the scheduled processor: once the user doc appears, the
 * order is counted normally; orders whose pending marker is older than
 * RELIABILITY_MISSING_USER_RETRY_MS are given up explicitly (MISSING_USER).
 *
 * This is the deferred-reconciliation complement to the trigger's own
 * retry path — together they guarantee a terminal event is never silently
 * dropped and never retried forever.
 *
 * @return {Promise<{counted: number, stillPending: number, errors: number}>}
 */
/**
 * Map an order's terminal status to its reliability outcome label.
 * @param {string} status
 * @return {string|null} "COLLECTED", "NO_SHOW", or null when not terminal.
 */
function reliabilityOutcomeFromStatus(status) {
  if (status === "collected") return "COLLECTED";
  if (status === "no_show") return "NO_SHOW";
  return null;
}

async function reconcilePendingReliabilityOrders() {
  let counted = 0;
  let stillPending = 0;
  let errors = 0;

  let pendingSnapshot;
  try {
    pendingSnapshot = await db
        .collection("orders")
        .where("reliabilityPending", "==", true)
        .limit(100)
        .get();
  } catch (err) {
    console.error("[PickupReliability] Reconcile query failed:", err);
    return { counted: 0, stillPending: 0, errors: 1 };
  }

  if (pendingSnapshot.size === 0) {
    return { counted: 0, stillPending: 0, errors: 0 };
  }

  console.log(
    `[PickupReliability] Reconcile: ${pendingSnapshot.size} pending order(s)`
  );

  const promises = pendingSnapshot.docs.map(async (orderSnapshot) => {
    try {
      const orderData = orderSnapshot.data();
      // The outcome is derivable from the order's terminal status; anything
      // else is a stale marker and is cleared.
      const outcome = reliabilityOutcomeFromStatus(orderData.status);

      if (outcome == null) {
        await orderSnapshot.ref.update({
          reliabilityPending: admin.firestore.FieldValue.delete(),
          reliabilityPendingSince: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      // processReliabilityEvent returns true when counted, false when given
      // up, and throws when the event is still deferred (user doc still
      // missing within the retry window).
      const processed = await processReliabilityEvent(
        orderSnapshot.ref,
        outcome,
      );
      if (processed) counted++;
    } catch (err) {
      // A deferral keeps the pending marker so the next scheduled run
      // retries it; any other failure is a real error and is reported.
      if (String(err && err.message).includes("deferred")) {
        stillPending++;
      } else {
        errors++;
        console.error(
          `[PickupReliability] Reconcile failed for order ${orderSnapshot.id}:`,
          err,
        );
      }
    }
  });

  await Promise.all(promises);
  return { counted, stillPending, errors };
}

exports.processExpiredPickups = functions
    .runWith({
      memory: "256MB",
      timeoutSeconds: 120,
    })
    .pubsub
    .schedule("every 1 minutes")
    .onRun(async (context) => {
      console.log("[PickupExpiry] Scheduled run started...");

      const now = admin.firestore.Timestamp.now();
      const graceExpiryThreshold = new admin.firestore.Timestamp(
        now.seconds - DEFAULT_PICKUP_GRACE_PERIOD_MINUTES * 60,
        now.nanoseconds,
      );
      let processedCount = 0;
      let errorCount = 0;
      // Store both studentId and orderId for the notification loop.
      // Using an array of objects ensures the orderId is accessible
      // outside the .map() callback scope.
      /** @type {Array<{studentId: string, orderId: string}>} */
      const processedRecords = [];

      try {
        const expiredOrdersSnapshot = await db
            .collection("orders")
            .where("status", "==", "ready")
            .where("deadlineStatus", "==", "ACTIVE")
            .where("pickupDeadline", "<=", graceExpiryThreshold)
            .get();

        console.log(`[PickupExpiry] Found ${expiredOrdersSnapshot.size} expired order(s)`);

        const promises = expiredOrdersSnapshot.docs.map(async (orderSnapshot) => {
          try {
            await db.runTransaction(async (transaction) => {
              const freshSnapshot = await transaction.get(orderSnapshot.ref);
              const processed = await processExpiredOrder(transaction, freshSnapshot);
              if (processed) {
                processedCount++;
                processedRecords.push({
                  studentId: orderSnapshot.data().studentId,
                  orderId: orderSnapshot.id,
                });
              }
            });
          } catch (err) {
            errorCount++;
            console.error(
              `[PickupExpiry] Failed to process an expired order:`, err
            );
          }
        });

        await Promise.all(promises);
      } catch (err) {
        console.error("[PickupExpiry] Query or processing error:", err);
        throw err;
      }

      console.log(
        `[PickupExpiry] Run complete: ${processedCount} processed, ${errorCount} errors`
      );

      // ── Notifications: Notify students about missed pickups ──
      // Only the ORDER_NO_SHOW notification is created — the strike engine
      // is removed, so no STRIKE_ISSUED / ACCOUNT_SUSPENDED notifications.
      // The eventId is per-order so a student who misses several orders
      // receives a notification for each one.
      if (processedCount > 0) {
        console.log(`[PickupExpiry] Creating notifications for ${processedRecords.length} student(s)`);
        for (const { studentId, orderId } of processedRecords) {
          try {
            await createNotification({
              recipientId: studentId,
              recipientRole: "student",
              type: "ORDER_NO_SHOW",
              title: "Order Missed",
              message: `You did not collect your order #${orderId} within the ` +
                       "pickup window and it has been marked as a no-show.",
              deepLink: "/orders",
              eventId: notificationEventId("ORDER_NO_SHOW", orderId),
              createdBy: "system",
            });
          } catch (notifErr) {
            console.error(
              `[PickupExpiry] Failed to create notification:`, notifErr
            );
          }
        }
      }

      // ── PICKUP_REMINDER: Notify students about orders nearing their deadline ──
      // Run after the expired-order processing so we don't send reminders
      // for orders that just expired.
      try {
        const reminderWindowMinutes = 5;
        const reminderThreshold = new admin.firestore.Timestamp(
          now.seconds + reminderWindowMinutes * 60,
          now.nanoseconds,
        );

        // Note: reminderSent is filtered client-side to avoid needing
        // a composite index with 4 equality/range/inequality fields.
        const nearingDeadlineOrders = await db
            .collection("orders")
            .where("status", "==", "ready")
            .where("deadlineStatus", "==", "ACTIVE")
            .where("pickupDeadline", "<=", reminderThreshold)
            .where("pickupDeadline", ">", now) // Not yet expired
            .get();

        // Filter client-side: only orders not yet reminded
        const ordersToRemind = nearingDeadlineOrders.docs.filter(
          (doc) => !doc.data().reminderSent
        );

        if (ordersToRemind.length > 0) {
          console.log(
            `[PickupExpiry] Sending PICKUP_REMINDER for ${ordersToRemind.length} order(s)`
          );

          const reminderPromises = ordersToRemind.map(
            async (orderDoc) => {
              const orderData = orderDoc.data();
              const studentId = orderData.studentId;
              if (!studentId) return;

              try {
                await createNotification({
                  recipientId: studentId,
                  recipientRole: "student",
                  type: "PICKUP_REMINDER",
                  title: "⏰ Pickup Reminder",
                  message: `Your order #${orderDoc.id} is almost ready for pickup! ` +
                           `Please collect it soon before the deadline expires.`,
                  orderId: orderDoc.id,
                  deepLink: `/orders/${orderDoc.id}`,
                  eventId: notificationEventId("PICKUP_REMINDER", orderDoc.id),
                  createdBy: "system",
                });

                // Mark the order as reminded to prevent duplicate reminders
                await orderDoc.ref.update({
                  reminderSent: true,
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
              } catch (notifErr) {
                console.error(
                  `[PickupExpiry] Failed to send PICKUP_REMINDER:`, notifErr
                );
              }
            },
          );

          await Promise.allSettled(reminderPromises);
        }
      } catch (reminderErr) {
        console.error("[PickupExpiry] PICKUP_REMINDER error:", reminderErr);
      }

      // ── Phase B.2 — reconcile deferred reliability events ────────────
      // Terminal events whose user document did not exist yet are marked
      // reliabilityPending by the trigger (never dropped). Cloud Functions
      // only redelivers a failed trigger event for a bounded window, so the
      // scheduled processor also reconciles them: orders whose user doc now
      // exists are counted, orders beyond the retry window are given up
      // explicitly (MISSING_USER), and still-missing orders are retried on
      // the next scheduled run.
      try {
        const reconcileResult = await reconcilePendingReliabilityOrders();
        console.log(
          `[PickupExpiry] Reliability reconcile: ` +
          `${reconcileResult.counted} counted, ` +
          `${reconcileResult.stillPending} still pending, ` +
          `${reconcileResult.errors} errors`
        );
      } catch (reconcileErr) {
        console.error(
          "[PickupExpiry] Reliability reconcile error:", reconcileErr
        );
      }

      return null;
    });

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION: extendPickupDeadline  (Callable — student extends their pickup)
// ════════════════════════════════════════════════════════════════════════════

/**
 * Number of minutes a single pickup-deadline extension adds.
 * Matches the customer app's PickupExtensionService.extensionMinutes.
 */
const PICKUP_EXTENSION_MINUTES = 10;

/**
 * Extend an order's pickup deadline by [PICKUP_EXTENSION_MINUTES].
 *
 * Students cannot update order documents directly (Firestore rules only
 * allow admin order updates), so this callable performs the write with the
 * Admin SDK. Enforced invariants:
 *
 *  - the caller must be authenticated (App Check enforced),
 *  - the caller must own the order,
 *  - the order must still be ready with an ACTIVE pickup deadline,
 *  - the extension is consumable exactly once per order,
 *  - the current pickup deadline must not have passed yet.
 *
 * All checks run inside a transaction so two concurrent taps cannot both
 * consume the single extension.
 */
exports.extendPickupDeadline = onCall(
  {
    authPolicy: "required",
    // Phase 15 — App Check: reject callers that cannot present a valid App
    // Check attestation token.
    enforceAppCheck: true,
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to extend a pickup."
      );
    }

    const uid = request.auth.uid;

    // ── Request envelope validation ───────────────────────────────
    const data = request.data;
    if (
      data === null ||
      typeof data !== "object" ||
      Array.isArray(data) ||
      JSON.stringify(data).length > 4096
    ) {
      throw new HttpsError("invalid-argument", "Invalid request payload.");
    }

    const envelopeKeys = Object.keys(data);
    if (envelopeKeys.length !== 1 || envelopeKeys[0] !== "orderId") {
      throw new HttpsError(
        "invalid-argument",
        "Request payload must contain exactly the orderId field."
      );
    }

    const { orderId } = data;
    if (
      !orderId ||
      typeof orderId !== "string" ||
      orderId.length === 0 ||
      orderId.length > 128 ||
      !/^[A-Za-z0-9_-]+$/.test(orderId)
    ) {
      throw new HttpsError("invalid-argument", "orderId is invalid.");
    }

    const orderRef = db.collection("orders").doc(orderId);

    try {
      const extendedDeadline = await db.runTransaction(async (transaction) => {
        const orderSnapshot = await transaction.get(orderRef);
        if (!orderSnapshot.exists) {
          throw new HttpsError("not-found", "Order not found.");
        }

        const orderData = orderSnapshot.data();

        // Ownership: only the student who placed the order may extend it.
        if (orderData.studentId !== uid) {
          throw new HttpsError(
            "permission-denied",
            "You can only extend your own orders."
          );
        }

        if (
          orderData.status !== "ready" ||
          orderData.deadlineStatus !== "ACTIVE"
        ) {
          throw new HttpsError(
            "failed-precondition",
            "This order can no longer be extended."
          );
        }

        if (orderData.deadlineExtended === true) {
          throw new HttpsError(
            "failed-precondition",
            "You have already extended the pickup for this order."
          );
        }

        const pickupDeadline = orderData.pickupDeadline;
        // Missing or non-Timestamp values fail cleanly instead of blowing up
        // on .toMillis()/.seconds below and surfacing as a generic error.
        if (!(pickupDeadline instanceof admin.firestore.Timestamp)) {
          throw new HttpsError(
            "failed-precondition",
            "This order has no valid pickup deadline and cannot be extended."
          );
        }

        const now = admin.firestore.Timestamp.now();
        if (pickupDeadline.toMillis() <= now.toMillis()) {
          throw new HttpsError(
            "failed-precondition",
            "The pickup deadline has already passed."
          );
        }

        const newDeadline = new admin.firestore.Timestamp(
          pickupDeadline.seconds + PICKUP_EXTENSION_MINUTES * 60,
          pickupDeadline.nanoseconds,
        );

        transaction.update(orderRef, {
          pickupDeadline: newDeadline,
          deadlineExtended: true,
          extensionAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return newDeadline;
      });

      console.log(
        `[extendPickupDeadline] Order ${orderId} extended by ` +
        `${PICKUP_EXTENSION_MINUTES} min → ${extendedDeadline.toDate().toISOString()}`
      );

      return {
        success: true,
        pickupDeadline: extendedDeadline.toDate().toISOString(),
      };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[extendPickupDeadline] Error:", err);
      throw new HttpsError(
        "internal",
        "Could not extend the pickup deadline. Please try again."
      );
    }
  },
);

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION: cancelOrder  (Callable — student cancels within the 2-minute window)
// ════════════════════════════════════════════════════════════════════════════

/**
 * Cancel an order within the [CANCELLATION_WINDOW_MINUTES]-minute window.
 *
 * Students cannot update order documents directly (Firestore rules only
 * allow admin order updates), so this callable performs the authoritative
 * transition with the Admin SDK. Enforced invariants:
 *
 *  - the caller must be authenticated (App Check enforced),
 *  - the caller must own the order,
 *  - the order must still be pending (not yet accepted by the cafe),
 *  - the current server time must be before the cancellation deadline,
 *  - the order's status history records cancelledAt / cancelledBy / reason.
 *
 * All checks run inside a transaction so a concurrent admin accept and a
 * student cancel can never both succeed — only one transition wins.
 */

/**
 * Validate the cancelOrder request envelope and payload.
 *
 * Enforces the allowed-key set (orderId + optional reason), the orderId
 * format/length and the bounded preset reason list.
 *
 * @param {Object} data — raw request.data payload
 * @return {{orderId: string, cancellationReason: string|null}}
 */
function validateCancelRequest(data) {
  if (
    data === null ||
    typeof data !== "object" ||
    Array.isArray(data) ||
    JSON.stringify(data).length > 4096
  ) {
    throw new HttpsError("invalid-argument", "Invalid request payload.");
  }

  const envelopeKeys = Object.keys(data);
  const validKeys = envelopeKeys.filter((k) => k === "orderId" || k === "reason");
  if (validKeys.length !== envelopeKeys.length || envelopeKeys.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "Request payload must contain only orderId and an optional reason."
    );
  }

  const { orderId, reason } = data;
  if (
    !orderId ||
    typeof orderId !== "string" ||
    orderId.length === 0 ||
    orderId.length > 128 ||
    !/^[A-Za-z0-9_-]+$/.test(orderId)
  ) {
    throw new HttpsError("invalid-argument", "orderId is invalid.");
  }

  // Optional cancellation reason: preset strings only, bounded length.
  let cancellationReason = null;
  if (reason !== undefined && reason !== null) {
    if (typeof reason !== "string" || reason.length === 0) {
      throw new HttpsError("invalid-argument", "reason is invalid.");
    }
    if (reason.length > 200) {
      throw new HttpsError(
        "invalid-argument",
        "reason must be 200 characters or fewer."
      );
    }
    const allowedReasons = [
      "Changed my mind",
      "Ordered by mistake",
      "Need to change my order",
      "Ordered the wrong item",
      "Other",
    ];
    if (!allowedReasons.includes(reason)) {
      throw new HttpsError(
        "invalid-argument",
        "reason is not an allowed cancellation reason."
      );
    }
    cancellationReason = reason;
  }

  return { orderId, cancellationReason };
}

exports.cancelOrder = onCall(
  {
    authPolicy: "required",
    enforceAppCheck: true,
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to cancel an order."
      );
    }

    const uid = request.auth.uid;
    const { orderId, cancellationReason } = validateCancelRequest(request.data);

    const orderRef = db.collection("orders").doc(orderId);

    try {
      await db.runTransaction(async (transaction) => {
        const orderSnapshot = await transaction.get(orderRef);
        if (!orderSnapshot.exists) {
          throw new HttpsError("not-found", "Order not found.");
        }

        const orderData = orderSnapshot.data();

        // Ownership: only the student who placed the order may cancel it.
        if (orderData.studentId !== uid) {
          throw new HttpsError(
            "permission-denied",
            "You can only cancel your own orders."
          );
        }

        // Only a PENDING order may be cancelled (not yet accepted).
        if (orderData.status !== "pending") {
          throw new HttpsError(
            "failed-precondition",
            "This order can no longer be cancelled."
          );
        }

        // The authoritative deadline is always derived from the
        // server-authoritative createdAt (the create rules require
        // createdAt == request.time, so it cannot be forged). The persisted
        // cancellationDeadline is display-only data for the client UI; it is
        // never trusted for the authoritative comparison, so a skewed or
        // missing stored value can neither extend nor shorten the window.
        // Deriving from createdAt also covers the pre-trigger gap: a brand
        // new order may not yet carry a stored deadline, but the window is
        // the same either way.
        const createdAt = orderData.createdAt;
        if (!(createdAt instanceof admin.firestore.Timestamp)) {
          throw new HttpsError(
            "failed-precondition",
            "This order has no cancellation window."
          );
        }
        const cancellationDeadline = new admin.firestore.Timestamp(
          createdAt.seconds + CANCELLATION_WINDOW_MINUTES * 60,
          createdAt.nanoseconds,
        );

        const now = admin.firestore.Timestamp.now();
        if (now.toMillis() >= cancellationDeadline.toMillis()) {
          throw new HttpsError(
            "failed-precondition",
            "The cancellation window has expired."
          );
        }

        transaction.update(orderRef, {
          status: "cancelled",
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          cancelledBy: uid,
          cancellationReason: cancellationReason,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return true;
      });

      // No user identifiers in logs (privacy): the caller UID is recorded in
      // the order document (cancelledBy) and the audit trail, not in log lines.
      console.log(`[cancelOrder] Order ${orderId} cancelled`);

      // ── Student notification (deduplicated by eventId) ──────────
      // Cancellation is a terminal state; the student is told the order
      // is cancelled so the UI never has to guess.
      try {
        await createNotification({
          recipientId: uid,
          recipientRole: "student",
          type: "ORDER_CANCELLED",
          title: "Order Cancelled",
          message: `Your order #${orderId} has been cancelled.`,
          orderId: orderId,
          deepLink: `/orders/${orderId}`,
          eventId: notificationEventId("ORDER_CANCELLED", orderId),
          createdBy: "system",
        });
      } catch (notifErr) {
        console.error(
          `[cancelOrder] Failed to create ORDER_CANCELLED notification:`, notifErr
        );
      }

      return { success: true };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[cancelOrder] Error:", err);
      throw new HttpsError(
        "internal",
        "Could not cancel the order. Please try again."
      );
    }
  },
);

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION: placeOrder  (Callable — Phase E authoritative order creation)
// ════════════════════════════════════════════════════════════════════════════
//
// Phase E — graduated ordering restrictions. Order creation is moved from a
// direct client Firestore write to this callable so the backend can enforce
// the active-order limit authoritatively (Firestore Rules cannot count
// documents across a collection, so a client-side write could bypass the
// limit). The existing onNewOrder trigger still runs on the created document
// (cancellation deadline, price normalization, foodIds backfill, admin
// notifications) — this callable only gates and creates.
//
// Enforcement (AGENTS.md Phase E §12-§14, §18):
//  - the caller must be authenticated (App Check enforced) and email-verified,
//  - the active-order limit is derived from the server-maintained
//    pickupReliability summary (Phase B data — never recomputed here),
//  - the active-order count is read INSIDE the same transaction that creates
//    the order, so two concurrent attempts can never both slip past the
//    limit,
//  - if the limit/verification cannot be determined the order is NOT created
//    (fail-safe; a client-side fallback is never allowed to bypass it).

// ── placeOrder helpers ────────────────────────────────────────────────────────
//
// The placeOrder callable is split into small single-purpose helpers so the
// onCall wrapper and the transaction callback both stay within the cognitive
// complexity budget while preserving every server-side validation.

function validatePlaceOrderEnvelope(data) {
  if (
    data === null ||
    typeof data !== "object" ||
    Array.isArray(data) ||
    JSON.stringify(data).length > 65536
  ) {
    throw new HttpsError("invalid-argument", "Invalid request payload.");
  }

  const allowedKeys = new Set([
    "orderId", "studentId", "userName", "items", "foodIds", "price",
    "cafeId", "cafeLocation", "distanceMeters", "distanceCalculated",
    "pickupWindowMinutes",
  ]);
  if (!Object.keys(data).every((k) => allowedKeys.has(k))) {
    throw new HttpsError(
      "invalid-argument",
      "Request payload contains unsupported fields."
    );
  }
}

function validateOrderIdentity(orderId, studentId, uid) {
  if (
    typeof orderId !== "string" ||
    orderId.length === 0 ||
    orderId.length > 64 ||
    !/^[A-Za-z0-9_-]+$/.test(orderId)
  ) {
    throw new HttpsError("invalid-argument", "orderId is invalid.");
  }
  if (studentId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "You can only place orders for your own account."
    );
  }
}

function validateUserAndOrderMeta(userName, items, price, pickupWindowMinutes) {
  if (typeof userName !== "string" || userName.length === 0 || userName.length > 100) {
    throw new HttpsError("invalid-argument", "userName is invalid.");
  }
  if (!Array.isArray(items) || items.length === 0 || items.length > 50) {
    throw new HttpsError("invalid-argument", "items is invalid.");
  }
  if (!Number.isFinite(price) || price < 0) {
    throw new HttpsError("invalid-argument", "price is invalid.");
  }
  if (
    !Number.isInteger(pickupWindowMinutes) ||
    pickupWindowMinutes < 10 ||
    pickupWindowMinutes > 25
  ) {
    throw new HttpsError("invalid-argument", "pickupWindowMinutes is invalid.");
  }
}

function validateOptionalFields(distanceCalculated, distanceMeters, cafeId) {
  if (typeof distanceCalculated !== "boolean") {
    throw new HttpsError("invalid-argument", "distanceCalculated is invalid.");
  }
  if (
    distanceMeters !== undefined &&
    distanceMeters !== null &&
    (!Number.isFinite(distanceMeters) || distanceMeters < 0)
  ) {
    throw new HttpsError("invalid-argument", "distanceMeters is invalid.");
  }
  if (cafeId !== undefined && cafeId !== null && typeof cafeId !== "string") {
    throw new HttpsError("invalid-argument", "cafeId is invalid.");
  }
}

function validateFoodIds(foodIds) {
  if (foodIds === undefined || foodIds === null) return;
  if (!Array.isArray(foodIds) || foodIds.length > 50) {
    throw new HttpsError("invalid-argument", "foodIds is invalid.");
  }
}

function validateCafeLocation(cafeLocation) {
  let cafeGeoPoint = null;
  if (cafeLocation !== undefined && cafeLocation !== null) {
    if (
      typeof cafeLocation !== "object" ||
      !Number.isFinite(cafeLocation.latitude) ||
      !Number.isFinite(cafeLocation.longitude)
    ) {
      throw new HttpsError("invalid-argument", "cafeLocation is invalid.");
    }
    cafeGeoPoint = new admin.firestore.GeoPoint(
      cafeLocation.latitude,
      cafeLocation.longitude
    );
  }
  return cafeGeoPoint;
}

function assertValidLineItem(item) {
  if (item === null || typeof item !== "object" || Array.isArray(item)) {
    throw new HttpsError("invalid-argument", "items is invalid.");
  }
  const foodItemId = item.foodItemId;
  if (typeof foodItemId !== "string" || foodItemId.length === 0 || foodItemId.length > 128) {
    throw new HttpsError("invalid-argument", "items is invalid.");
  }
  const quantity = item.quantity;
  if (!Number.isInteger(quantity) || quantity <= 0 || quantity >= 100) {
    throw new HttpsError("invalid-argument", "items is invalid.");
  }
  const itemPrice = item.price;
  if (!Number.isFinite(itemPrice) || itemPrice < 0) {
    throw new HttpsError("invalid-argument", "items is invalid.");
  }
}

function normalizeLineItems(items) {
  return items.map((item) => {
    assertValidLineItem(item);
    return {
      foodItemId: item.foodItemId,
      title: typeof item.title === "string" ? item.title.slice(0, 200) : "",
      price: item.price,
      quantity: item.quantity,
      image: typeof item.image === "string" ? item.image.slice(0, 2000) : "",
      selectedCafe: typeof item.selectedCafe === "string"
        ? item.selectedCafe.slice(0, 100)
        : null,
    };
  });
}

function assertSingleCafe(lineItems) {
  const distinctCafes = new Set();
  let hasCafelessItem = false;
  for (const item of lineItems) {
    const cafe = typeof item.selectedCafe === "string" &&
        item.selectedCafe.trim().length > 0
      ? item.selectedCafe.trim()
      : null;
    if (cafe === null) hasCafelessItem = true;
    else distinctCafes.add(cafe);
  }
  if (distinctCafes.size > 1 || (distinctCafes.size === 1 && hasCafelessItem)) {
    throw new HttpsError(
      "invalid-argument",
      "You can only order from one cafe per order. Please place separate orders for items from different cafes."
    );
  }
}

function parsePlaceOrderRequest(data, uid) {
  validatePlaceOrderEnvelope(data);
  const {
    orderId, studentId, userName, items, foodIds, price, cafeId,
    cafeLocation, distanceMeters, distanceCalculated, pickupWindowMinutes,
  } = data;
  validateOrderIdentity(orderId, studentId, uid);
  validateUserAndOrderMeta(userName, items, price, pickupWindowMinutes);
  validateOptionalFields(distanceCalculated, distanceMeters, cafeId);
  validateFoodIds(foodIds);
  const cafeGeoPoint = validateCafeLocation(cafeLocation);
  const lineItems = normalizeLineItems(items);
  assertSingleCafe(lineItems);
  return {
    orderId,
    userName,
    lineItems,
    foodIds,
    price,
    cafeId,
    cafeGeoPoint,
    distanceMeters,
    distanceCalculated,
    pickupWindowMinutes,
  };
}

async function assertActiveOrderLimit(transaction, uid, limit) {
  const activeSnapshot = await transaction.get(
    db.collection("orders")
      .where("studentId", "==", uid)
      .where("status", "in", ACTIVE_ORDER_STATUSES)
  );
  if (activeSnapshot.size >= limit) {
    throw new HttpsError(
      "failed-precondition",
      limit === 1
        ? "You currently have an active order. Please collect it before placing another order."
        : "You currently have " + limit +
          " active orders. Collect one before placing another order.",
      { code: "ACTIVE_ORDER_LIMIT", activeOrderLimit: limit }
    );
  }
}

async function assertFoodsAvailable(transaction, lineItems) {
  for (const item of lineItems) {
    const foodSnapshot = await transaction.get(
      db.collection("food_items").doc(item.foodItemId)
    );
    const available = foodSnapshot.exists
      ? foodSnapshot.data().available !== false
      : false;
    if (!available) {
      throw new HttpsError(
        "failed-precondition",
        "Some items are no longer available.",
        { code: "ITEMS_UNAVAILABLE" }
      );
    }
  }
}

function buildOrderData(ctx) {
  const derivedCafes = deriveOrderCafes(ctx.lineItems);
  return {
    orderId: ctx.orderId,
    studentId: ctx.uid,
    userName: ctx.userName,
    items: ctx.lineItems,
    foodIds: Array.isArray(ctx.foodIds) && ctx.foodIds.length > 0
      ? ctx.foodIds
      : ctx.lineItems.map((i) => i.foodItemId),
    price: ctx.price,
    cafeId: ctx.cafeId !== undefined && ctx.cafeId !== null ? ctx.cafeId : null,
    cafeLocation: ctx.cafeGeoPoint,
    distanceMeters: ctx.distanceMeters !== undefined && ctx.distanceMeters !== null
      ? ctx.distanceMeters
      : null,
    distanceCalculated: ctx.distanceCalculated,
    pickupWindowMinutes: ctx.pickupWindowMinutes,
    status: "pending",
    deadlineStatus: "NOT_READY",
    noShowProcessed: false,
    deadlineExtended: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    cafes: derivedCafes || [UNASSIGNED_CAFE],
  };
}

async function placeOrderInTransaction(transaction, ctx) {
  const userSnapshot = await transaction.get(ctx.userRef);
  if (!userSnapshot.exists || userSnapshot.data().role !== "student") {
    throw new HttpsError(
      "unavailable",
      "Unable to verify your active orders. Please try again."
    );
  }
  const userData = userSnapshot.data();
  if (userData.accountStatus === "SUSPENDED") {
    throw new HttpsError(
      "permission-denied",
      "Your account is suspended and cannot place orders."
    );
  }
  const summary = userData.pickupReliability &&
      typeof userData.pickupReliability === "object"
    ? userData.pickupReliability
    : null;
  const limit = restrictionFor(summary).activeOrderLimit;

  if (limit != null) {
    await assertActiveOrderLimit(transaction, ctx.uid, limit);
  }

  const existingOrder = await transaction.get(ctx.orderRef);
  if (existingOrder.exists) {
    throw new HttpsError(
      "already-exists",
      "This order has already been placed."
    );
  }

  await assertFoodsAvailable(transaction, ctx.lineItems);

  if (limit != null) {
    transaction.update(ctx.userRef, {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  transaction.set(ctx.orderRef, buildOrderData(ctx));
  return ctx.orderId;
}

exports.placeOrder = onCall(
  {
    authPolicy: "required",
    enforceAppCheck: true,
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to place an order."
      );
    }

    const uid = request.auth.uid;
    const token = request.auth.token || {};
    if (token.email_verified !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Please verify your email before placing an order.",
        { code: "EMAIL_NOT_VERIFIED" }
      );
    }

    const payload = parsePlaceOrderRequest(request.data, uid);
    const orderRef = db.collection("orders").doc(payload.orderId);
    const userRef = db.collection("users").doc(uid);

    try {
      const placedOrderId = await db.runTransaction((transaction) =>
        placeOrderInTransaction(transaction, {
          uid,
          orderRef,
          userRef,
          ...payload,
        })
      );

      console.log(`[placeOrder] Order ${placedOrderId} placed`);
      return { success: true, orderId: placedOrderId, orderStatus: "pending" };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[placeOrder] Error:", err);
      throw new HttpsError(
        "internal",
        "Could not place the order. Please try again."
      );
    }
  },
);

// ── Order foodIds backfill ────────────────────────────────────────────────────
//
// The review-eligibility security rule (validReviewOrderEligibility) verifies
// that a reviewed food was actually in a COLLECTED order by checking the
// denormalised `foodIds` array.  Orders created before that field existed
// (legacy orders) or by legacy app builds lack it and would be permanently
// non-reviewable, because the rules language cannot iterate the nested
// `items` maps to derive the IDs at write time — and students are not
// allowed to update order documents.
//
// These helpers backfill `foodIds` server-side (admin SDK bypasses the
// student-write restriction on orders) by deriving the IDs from the nested
// `items` data — the authoritative purchase record.  The presence check and
// the write run inside a single Firestore transaction (the order is re-read
// immediately before the write), and ANY existing `foodIds` value — a
// populated list, an empty array, or a malformed historical value — aborts
// the backfill so existing data is never clobbered or reinterpreted.

/**
 * Derive the deduplicated `foodIds` list from an order's nested `items` array.
 * @param {*} items — the order's `items` field
 * @return {string[]|null} — derived food IDs, or null when none can be derived
 */
function deriveOrderFoodIds(items) {
  if (!Array.isArray(items)) return null;
  const foodIds = [];
  for (const item of items) {
    if (!item || typeof item !== "object") continue;
    const id = item.foodItemId || item.id;
    if (typeof id === "string" && id.length > 0 && !foodIds.includes(id)) {
      foodIds.push(id);
    }
  }
  return foodIds.length > 0 ? foodIds : null;
}

/**
 * Backfill `foodIds` on an order document when the field is absent.
 *
 * The presence check and the write are performed inside a single Firestore
 * transaction: the order is re-read immediately before the write, so a
 * concurrent write can never slip in between the check and the update, and
 * the transaction aborts (retrying) if the document changed since the
 * trigger's snapshot.
 *
 * ANY existing `foodIds` value — a populated list, an empty array, or a
 * malformed historical value — aborts the backfill: the field was written
 * either by the creating client or by a prior backfill, so it is never
 * clobbered or reinterpreted.
 *
 * @param {admin.firestore.DocumentReference} orderRef
 * @param {Object} orderData — the trigger snapshot, used only for the early
 *   no-data guard; the authoritative presence check re-reads the document
 *   inside the transaction.
 * @return {Promise<boolean>} true when a backfill write was performed
 */
async function backfillOrderFoodIds(orderRef, orderData) {
  if (!orderData) return false;
  const migrated = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(orderRef);
    if (!snapshot.exists) return false;
    const data = snapshot.data();
    // Presence of the field with ANY value means it is already populated —
    // never overwrite or reinterpret empty/malformed historical values.
    if (data.foodIds !== undefined) return false;
    const foodIds = deriveOrderFoodIds(data.items);
    if (!foodIds) return false; // Nothing derivable — leave unchanged.
    transaction.update(orderRef, {
      foodIds,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (migrated) {
    console.log("[backfillFoodIds] Backfilled foodIds for order");
  }
  return migrated;
}

// ── Order cafes backfill ─────────────────────────────────────────────────────
//
// Admin order access is scoped per cafe (firestore.rules adminServesOrder()):
// an admin may read/update only orders whose server-authoritative `cafes`
// array contains the admin's own `cafeName`.  The `cafes` array is derived
// from the validated line items' `selectedCafe` values and written by the
// backend (placeOrder on create, these helpers for legacy orders) — the
// rules protect the field from ALL client writes, so it cannot be forged.

// Sentinel value for genuinely cafeless orders (no line item has a resolvable
// cafe). It guarantees every order carries a non-empty `cafes` list so per-cafe
// scoping is never bypassed by an absent/empty value; such orders are served
// by any active admin (firestore.rules adminServesOrder()) and are delivered
// to every admin in NEW_ORDER notifications, mirroring the legacy
// "notify all admins" fallback.
const UNASSIGNED_CAFE = "UNASSIGNED";

// Phase H — Cafe Food Waste Management. Controlled food-disposition types
// (AGENTS.md Phase H §2). UNRESOLVED is the default state when an order
// becomes NO_SHOW (§3); the remaining values are chosen by an authorized
// cafe admin through the setFoodDisposition callable. RESOLD/DISCOUNTED/
// DONATED/DISPOSED/STAFF_USE/OTHER are operational records only — they never
// change the order status or the student's reliability (§20-§21).
const FOOD_DISPOSITIONS = [
  "UNRESOLVED",
  "RESOLD",
  "DISCOUNTED",
  "DONATED",
  "STAFF_USE",
  "DISPOSED",
  "OTHER",
];

/**
 * Derive the deduplicated, non-empty `cafes` list from an order's nested
 * `items` array (the cafe each line item was ordered from).
 * @param {*} items — the order's `items` field
 * @return {string[]|null} — derived cafe names, or null when none can be
 *   derived
 */
function deriveOrderCafes(items) {
  if (!Array.isArray(items)) return null;
  const cafes = [];
  for (const item of items) {
    if (!item || typeof item !== "object") continue;
    const cafe = typeof item.selectedCafe === "string" ? item.selectedCafe.trim() : "";
    if (cafe.length > 0 && !cafes.includes(cafe)) {
      cafes.push(cafe);
    }
  }
  return cafes.length > 0 ? cafes : null;
}

/**
 * True when `cafes` is a populated list of non-empty strings — the only
 * representation the scoping rules accept as authoritative.
 * @param {*} cafes
 * @return {boolean}
 */
function isValidCafesList(cafes) {
  return (
    Array.isArray(cafes) &&
    cafes.length > 0 &&
    cafes.every((c) => typeof c === "string" && c.trim().length > 0)
  );
}

/**
 * Normalize the server-authoritative `cafes` list on an order document.
 *
 * The check and the write run inside a single Firestore transaction (the
 * order is re-read immediately before the write). An order is repaired when
 * its `cafes` field is absent, an empty array, or otherwise malformed: the
 * derived list is written when the line items resolve to at least one cafe,
 * otherwise the UNASSIGNED sentinel is written so the order still carries a
 * non-empty scoping list that any admin may serve. Existing valid
 * (non-empty, string) lists are left untouched — never clobbered or
 * reinterpreted.
 *
 * @param {admin.firestore.DocumentReference} orderRef
 * @param {Object} orderData — the trigger snapshot, used only for the early
 *   no-data guard; the authoritative check re-reads the document inside the
 *   transaction.
 * @return {Promise<boolean>} true when a backfill write was performed
 */
async function backfillOrderCafes(orderRef, orderData) {
  if (!orderData) return false;
  const migrated = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(orderRef);
    if (!snapshot.exists) return false;
    const data = snapshot.data();
    // Absent, empty, or malformed values are repaired; a valid non-empty
    // list is authoritative and left exactly as-is (idempotent no-op).
    if (isValidCafesList(data.cafes)) return false;
    const derived = deriveOrderCafes(data.items);
    const cafes = derived ? derived : [UNASSIGNED_CAFE];
    transaction.update(orderRef, {
      cafes,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (migrated) {
    console.log("[backfillCafes] Backfilled cafes for order");
  }
  return migrated;
}

/**
 * Recompute an order's authoritative line-item pricing from the current
 * `food_items` collection and correct the stored order when the client-side
 * figures diverge.
 *
 * Phase 15 — order financial integrity (Part 10/12). The student's
 * Firestore rules cannot iterate the nested `items` maps, so a forged price
 * (understated total, tampered line-item unit price) cannot be rejected in
 * rules. This server-side normalizer fixes the store order document to use
 * the actual menu price for every purchased item (and quantity), so the
 * total the cafeteria sees is always derived from the source of truth.
 *
 * The order is HELD (a retriable error is thrown) whenever any line item
 * cannot be priced authoritatively: the food doc is missing, its lookup
 * fails, its menu price is not a finite number, or the quantity is not a
 * positive integer. The client-supplied price is never used as a fallback
 * and no partial total is ever persisted.
 *
 * @param {admin.firestore.DocumentReference} orderRef
 * @param {Object} orderData
 * @return {Promise<number|null>} the recomputed authoritative total, or
 *   null when no correction was made (pricing already authoritative).
 */
/**
 * Resolve the authoritative unit price and quantity for one line item from
 * its `food_items` document. Throws (holding the order) when the item cannot
 * be priced: no food ID, lookup failure, missing doc, non-finite menu price,
 * or non-positive quantity. Never falls back to the client-supplied price.
 *
 * @param {admin.firestore.DocumentReference} orderRef
 * @param {*} item — a line item from `orderData.items`
 * @return {Promise<{unitPrice: number, quantity: number}>}
 */
async function resolveLineItemPrice(orderRef, item) {
  const foodId = item && (item.foodItemId || item.id);

  if (typeof foodId !== "string" || foodId.length === 0) {
    throw new TypeError(
      `[normalizeOrderPricing] Order ${orderRef.id} has an item without a ` +
      `food ID — holding order`
    );
  }

  let snap;
  try {
    snap = await orderRef.firestore
        .collection("food_items")
        .doc(foodId)
        .get();
  } catch (err) {
    console.warn(
      `[normalizeOrderPricing] food_items/${foodId} lookup failed: ${err.message}`
    );
    throw new Error(
      `[normalizeOrderPricing] Order ${orderRef.id} food_items/${foodId} ` +
      `lookup failed — holding order`,
      { cause: err },
    );
  }
  if (!snap.exists) {
    throw new Error(
      `[normalizeOrderPricing] Order ${orderRef.id} references missing ` +
      `food_items/${foodId} — holding order`
    );
  }
  const menuData = snap.data();
  const unitPrice = menuData && menuData.price;
  const quantity = item && item.quantity;

  if (typeof unitPrice !== "number" || !Number.isFinite(unitPrice)) {
    throw new Error(
      `[normalizeOrderPricing] food_items/${foodId} has no finite price — ` +
      `cannot price order ${orderRef.id} — holding order`
    );
  }
  if (typeof quantity !== "number" || !Number.isInteger(quantity) || quantity <= 0) {
    throw new Error(
      `[normalizeOrderPricing] Order ${orderRef.id} item ${foodId} has ` +
      `invalid quantity (${quantity}) — holding order`
    );
  }

  return { unitPrice, quantity };
}

/**
 * Whether the stored order pricing (total and per-item unit prices) diverges
 * from the authoritative figures and therefore needs a corrective write.
 *
 * @param {number} resolvedTotalValue — recomputed authoritative total
 * @param {Array<{price: number, quantity: number}>} prices
 * @param {Object} orderData
 * @return {boolean}
 */
function pricingNeedsCorrection(resolvedTotalValue, prices, orderData) {
  const storedTotal =
    typeof orderData.price === "number" ? orderData.price : 0;
  const needsPriceFix = Math.abs(resolvedTotalValue - storedTotal) > 0.001;
  const needsItemFix = prices.some(
    (p, i) => p.price !== (orderData.items[i] && orderData.items[i].price)
  );
  return needsPriceFix || needsItemFix;
}

async function normalizeOrderPricing(orderRef, orderData) {
  if (!orderData || !Array.isArray(orderData.items) || orderData.items.length === 0) {
    return null;
  }

  const resolvedTotal = { value: 0 };
  const prices = [];

  for (const item of orderData.items) {
    // Every line item must resolve to an authoritative menu record — never
    // fall back to the client-supplied price. A missing or unreadable
    // record holds the order (the trigger's retry policy redelivers the
    // event) until the menu is authoritative again.
    //
    // Trade-off: because the throw precedes notification creation, a held
    // order delays (and, if the item never reappears, ultimately drops) its
    // NEW_ORDER admin notification. In practice CartService re-reads every
    // food_items doc inside the order-placement transaction and aborts on
    // missing items, so a missing doc at trigger time is a rare anomaly
    // (deleted post-placement / legacy order) and the retry is bounded by
    // the Cloud Functions retry window.
    const { unitPrice, quantity } = await resolveLineItemPrice(orderRef, item);
    prices.push({ price: unitPrice, quantity });
    resolvedTotal.value += unitPrice * quantity;
  }

  if (!pricingNeedsCorrection(resolvedTotal.value, prices, orderData)) {
    return null;
  }

  const lineItems = orderData.items.map((item, i) => ({ ...item, price: prices[i].price }));
  await orderRef.update({
    items: lineItems,
    price: resolvedTotal.value,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(
    `[normalizeOrderPricing] Corrected order pricing → Tsh ${resolvedTotal.value}`
  );
  return resolvedTotal.value;
}

// ════════════════════════════════════════════════════════════════════════════
// PHASE B.2 — PICKUP RELIABILITY ENGINE
// ════════════════════════════════════════════════════════════════════════════
//
// Event-driven, server-authoritative reliability measurement. Only genuine
// terminal pickup outcomes (COLLECTED / NO_SHOW) update a student's
// reliability summary — cancelled, rejected, and never-READY orders never
// count. The summary lives in the existing `users/{uid}.pickupReliability`
// nested map (no new collection, no full order-history scans).
//
// Idempotency: each order carries a `reliabilityProcessed` marker that is
// set in the SAME Firestore transaction that updates the summary, so a
// redelivered event can never double-count. The recent-history window is
// capped at RECENT_PICKUP_WINDOW_SIZE entries and the same order can never
// appear twice (marker + explicit orderId filter).

/**
 * Default reliability summary for a student with no pickup history.
 * @return {Object}
 */
function emptyReliabilitySummary() {
  return {
    eligibleOrders: 0,
    collectedOrders: 0,
    noShowOrders: 0,
    collectionRate: 100,
    recentEligibleOrders: 0,
    recentCollectedOrders: 0,
    recentNoShowOrders: 0,
    recentCollectionRate: 100,
    reliabilityScore: 100,
    status: "NEW",
    // Phase E — a new user is never restricted (eligibleOrders == 0).
    restrictionLevel: RESTRICTION_LEVEL_NORMAL,
    restrictionReason: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    recentPickupHistory: [],
  };
}

/**
 * Round a 0-100 rate/score to one decimal place to keep stored values
 * predictable without cumulative rounding errors in intermediate steps.
 * @param {number} value
 * @return {number}
 */
function roundRate(value) {
  return Math.round(value * 10) / 10;
}

/**
 * Milliseconds for a Firestore Timestamp, Date, or missing history timestamp.
 * Used to keep recentPickupHistory ordered by the actual terminal event time
 * so a delayed or out-of-order event can never evict a genuinely newer one.
 * @param {*} value — Timestamp, Date, or null/undefined
 * @return {number}
 */
function historyTimestampMillis(value) {
  if (value instanceof admin.firestore.Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return 0;
}

/**
 * Classify a reliability score into an informational status.
 *
 * Minimum-history rule: 0 eligible → NEW; 1-2 eligible →
 * INSUFFICIENT_HISTORY (raw metrics still computed, no conclusion drawn);
 * 3+ eligible → normal thresholds. Never punishes a new user.
 *
 * @param {number} eligibleOrders
 * @param {number} score
 * @return {string}
 */
function reliabilityStatusFor(eligibleOrders, score) {
  if (eligibleOrders === 0) return "NEW";
  if (eligibleOrders <= 2) return "INSUFFICIENT_HISTORY";
  if (score >= 90) return "EXCELLENT";
  if (score >= 75) return "GOOD";
  if (score >= 50) return "NEEDS_IMPROVEMENT";
  if (score >= 25) return "POOR";
  return "CRITICAL";
}

// ════════════════════════════════════════════════════════════════════════════
// PHASE E — GRADUATED ORDERING RESTRICTIONS
// ════════════════════════════════════════════════════════════════════════════
//
// Restrictions are DERIVED server-side from the existing Phase B reliability
// summary. The reliability engine remains the single source of truth; the
// restriction layer never recalculates reliability independently and never
// runs inside Flutter. There are NO strikes, NO suspensions and NO permanent
// bans — restrictions are gradual, reversible and follow the current
// reliability state.
//
// Policy (AGENTS.md Phase E §3, §4-§6):
//   eligibleOrders < 3              → NORMAL        (insufficient evidence)
//   score >= 90   (EXCELLENT)       → NORMAL
//   score 50-89   (GOOD/NEEDS_IMP)  → NORMAL        (WARNING is informational)
//   score 25-49   (POOR)            → LIMITED        (max 2 active orders)
//   score 0-24    (CRITICAL)        → HIGHLY_LIMITED (max 1 active order)

/**
 * Explicit restriction levels (AGENTS.md Phase E §9). BANNED / SUSPENDED /
 * STRIKE / PUNISHED are intentionally NOT used by this system.
 */
const RESTRICTION_LEVEL_NORMAL = "NORMAL";
const RESTRICTION_LEVEL_LIMITED = "LIMITED";
const RESTRICTION_LEVEL_HIGHLY_LIMITED = "HIGHLY_LIMITED";

/**
 * Order statuses that count toward the active-order limit (Phase E §10):
 * PENDING, ACCEPTED, PREPARING, READY. Terminal states (CANCELLED, COLLECTED,
 * NO_SHOW, REJECTED) never count. Mirrors the canonical OrderStatus values.
 */
const ACTIVE_ORDER_STATUSES = ["pending", "accepted", "preparing", "ready"];

/**
 * Derive the ordering restriction from an authoritative reliability summary.
 *
 * The same function backs both the restriction engine (which writes
 * restrictionLevel/restrictionReason into the summary on every reliability
 * event) and the order-creation callable (which enforces the limit for
 * students whose stored summary predates Phase E). It reads ONLY the
 * server-maintained summary fields — it never recomputes reliability.
 *
 * @param {Object|undefined} summary — pickupReliability map (or none)
 * @return {{restrictionLevel: string, restrictionReason: string|null, activeOrderLimit: number|null}}
 */
function restrictionFor(summary) {
  const eligibleOrders = summary && Number.isFinite(summary.eligibleOrders)
    ? summary.eligibleOrders
    : 0;
  // Use the UNROUNDED score so the restriction threshold aligns exactly with
  // the reliability status threshold (a boundary value such as 24.96 is
  // CRITICAL → HIGHLY_LIMITED, never nudged into LIMITED by rounding).
  const score = summary && Number.isFinite(summary.reliabilityScore)
    ? summary.reliabilityScore
    : 100;

  if (eligibleOrders < 3) {
    // §4-§6 — insufficient history: no restriction, regardless of score.
    return {
      restrictionLevel: RESTRICTION_LEVEL_NORMAL,
      restrictionReason: null,
      activeOrderLimit: null,
    };
  }
  if (score >= 50) {
    // §1-§2 — EXCELLENT / GOOD / NEEDS_IMPROVEMENT: normal ordering (the
    // WARNING band is informational only; it carries no order limit).
    return {
      restrictionLevel: RESTRICTION_LEVEL_NORMAL,
      restrictionReason: null,
      activeOrderLimit: null,
    };
  }
  if (score >= 25) {
    // §3 — POOR: at most 2 active orders.
    return {
      restrictionLevel: RESTRICTION_LEVEL_LIMITED,
      restrictionReason: "Low pickup reliability",
      activeOrderLimit: 2,
    };
  }
  // §3 — CRITICAL: at most 1 active order.
  return {
    restrictionLevel: RESTRICTION_LEVEL_HIGHLY_LIMITED,
    restrictionReason: "Very low pickup reliability",
    activeOrderLimit: 1,
  };
}

/**
 * Recompute a student's reliability summary after one terminal pickup event.
 *
 * Weighted model: 70% lifetime collection rate + 30% recent (last 10)
 * collection rate. Zero-eligible handling keeps rates/score at 100 with
 * status NEW (no NaN, no division by zero, no "0%" for a new user).
 *
 * @param {Object|undefined} existing — current pickupReliability map (or none)
 * @param {'COLLECTED'|'NO_SHOW'} outcome
 * @param {string} orderId
 * @param {admin.firestore.Timestamp} timestamp — event timestamp for history
 * @return {Object} the new summary map (safe to write as a nested map)
 */
function recomputeReliability(existing, outcome, orderId, timestamp) {
  // Start from the neutral NEW defaults so every field has a concrete value
  // even when the student has no summary yet (never 0% for a new user).
  const prev = existing && typeof existing === "object"
    ? { ...emptyReliabilitySummary(), ...existing }
    : emptyReliabilitySummary();
  const history = Array.isArray(prev.recentPickupHistory)
    ? prev.recentPickupHistory.filter((e) => e && e.orderId !== orderId)
    : [];
  // The marker guarantees the order was not counted before; the filter above
  // is defence-in-depth so a legacy/foreign duplicate can never double-count.
  history.push({ orderId, outcome, timestamp });
  // Retain the latest RECENT_PICKUP_WINDOW_SIZE by ACTUAL event time, not
  // insertion order: events can arrive out of order (a delayed trigger, a
  // scheduled no-show processed after a later collection), and trimming the
  // front of an unsorted list would evict the wrong entries.
  history.sort(
    (a, b) => historyTimestampMillis(a.timestamp) - historyTimestampMillis(b.timestamp),
  );
  if (history.length > RECENT_PICKUP_WINDOW_SIZE) {
    history.splice(0, history.length - RECENT_PICKUP_WINDOW_SIZE);
  }

  const eligibleOrders = prev.eligibleOrders + 1;
  const collectedOrders =
    prev.collectedOrders + (outcome === "COLLECTED" ? 1 : 0);
  const noShowOrders =
    prev.noShowOrders + (outcome === "NO_SHOW" ? 1 : 0);

  // Unrounded rates drive the weighted score so rounding is applied exactly
  // once, on the values that are stored/displayed. Rounding the inputs first
  // would skew the weighted result (e.g. 80.952…% → 81.0 before the 0.7
  // weight). Empty-order defaults (100) are preserved.
  const rawCollectionRate =
    eligibleOrders === 0
      ? 100
      : (collectedOrders / eligibleOrders) * 100;

  const recentEligibleOrders = history.length;
  const recentCollectedOrders = history.filter(
    (e) => e.outcome === "COLLECTED"
  ).length;
  const recentNoShowOrders = history.filter(
    (e) => e.outcome === "NO_SHOW"
  ).length;
  const rawRecentCollectionRate =
    recentEligibleOrders === 0
      ? 100
      : (recentCollectedOrders / recentEligibleOrders) * 100;

  const rawReliabilityScore =
    eligibleOrders === 0
      ? 100
      : rawCollectionRate * 0.7 + rawRecentCollectionRate * 0.3;

  // Round only for storage/display; the status threshold check uses the
  // unrounded score so a boundary value (e.g. 74.96) is classified
  // accurately instead of being nudged across a threshold by rounding.
  const collectionRate = roundRate(rawCollectionRate);
  const recentCollectionRate = roundRate(rawRecentCollectionRate);
  const reliabilityScore = roundRate(rawReliabilityScore);
  const status = reliabilityStatusFor(eligibleOrders, rawReliabilityScore);

  // Phase E — graduated ordering restriction derived from the authoritative
  // summary on every event. The summary write is already event-driven
  // (COLLECTED / NO_SHOW only), so deriving the restriction here adds NO
  // extra Firestore writes, and the level always follows the current score
  // (recovery is automatic when the score crosses a threshold).
  const restriction = restrictionFor({
    eligibleOrders,
    reliabilityScore: rawReliabilityScore,
  });

  return {
    eligibleOrders,
    collectedOrders,
    noShowOrders,
    collectionRate,
    recentEligibleOrders,
    recentCollectedOrders,
    recentNoShowOrders,
    recentCollectionRate,
    reliabilityScore,
    status,
    restrictionLevel: restriction.restrictionLevel,
    restrictionReason: restriction.restrictionReason,
    updatedAt: timestamp,
    recentPickupHistory: history,
  };
}

/**
 * Recompute a student's reliability summary after an admin EXCUSES one
 * no-show (Phase G — ADMIN INTERVENTION).
 *
 * Excusing is a correction to a counted event, NOT a rewrite of history:
 * the order stays NO_SHOW, but the event stops counting as an unexcused
 * failed pickup. The excused order is removed from recentPickupHistory
 * (omission — never converted to COLLECTED, so it counts as neither
 * success nor failure) and the lifetime eligible/no-show counters are
 * decremented by one. All rates, score, status and the Phase E restriction
 * are then recomputed with the SAME formulas as [recomputeReliability] so
 * the correction is consistent with the incremental engine.
 *
 * Callers must only invoke this when the excused no-show was actually
 * counted (reliabilityProcessed === true && reliabilityOutcome ===
 * 'NO_SHOW'); otherwise subtracting would corrupt an uncounted summary.
 *
 * @param {Object|undefined} existing — current pickupReliability map (or none)
 * @param {string} orderId — the excused order to exclude
 * @param {admin.firestore.Timestamp} timestamp — intervention time
 * @return {Object} the corrected summary map (safe to write as a nested map)
 */
function recomputeReliabilityAfterExcuse(existing, orderId, timestamp) {
  const prev = existing && typeof existing === "object"
    ? { ...emptyReliabilitySummary(), ...existing }
    : emptyReliabilitySummary();
  const history = Array.isArray(prev.recentPickupHistory)
    ? prev.recentPickupHistory.filter((e) => e && e.orderId !== orderId)
    : [];

  const eligibleOrders = Math.max(0, prev.eligibleOrders - 1);
  const collectedOrders = prev.collectedOrders;
  const noShowOrders = Math.max(0, prev.noShowOrders - 1);

  const rawCollectionRate =
    eligibleOrders === 0
      ? 100
      : (collectedOrders / eligibleOrders) * 100;

  const recentEligibleOrders = history.length;
  const recentCollectedOrders = history.filter(
    (e) => e.outcome === "COLLECTED"
  ).length;
  const recentNoShowOrders = history.filter(
    (e) => e.outcome === "NO_SHOW"
  ).length;
  const rawRecentCollectionRate =
    recentEligibleOrders === 0
      ? 100
      : (recentCollectedOrders / recentEligibleOrders) * 100;

  const rawReliabilityScore =
    eligibleOrders === 0
      ? 100
      : rawCollectionRate * 0.7 + rawRecentCollectionRate * 0.3;

  const collectionRate = roundRate(rawCollectionRate);
  const recentCollectionRate = roundRate(rawRecentCollectionRate);
  const reliabilityScore = roundRate(rawReliabilityScore);
  const status = reliabilityStatusFor(eligibleOrders, rawReliabilityScore);

  const restriction = restrictionFor({
    eligibleOrders,
    reliabilityScore: rawReliabilityScore,
  });

  return {
    eligibleOrders,
    collectedOrders,
    noShowOrders,
    collectionRate,
    recentEligibleOrders,
    recentCollectedOrders,
    recentNoShowOrders,
    recentCollectionRate,
    reliabilityScore,
    status,
    restrictionLevel: restriction.restrictionLevel,
    restrictionReason: restriction.restrictionReason,
    updatedAt: timestamp,
    recentPickupHistory: history,
  };
}

/**
 * Process a terminal pickup event (COLLECTED or NO_SHOW) for one order.
 *
 * Runs inside a Firestore transaction so the student summary update and the
 * order's `reliabilityProcessed` marker commit atomically: a concurrent or
 * redelivered event can never double-count, and two simultaneous terminal
 * events for the same student are serialised correctly by the transaction.
 *
 * When the student's user document does not exist (deleted user, or a user
 * doc created only AFTER the order reached a terminal state), the event is
 * DEFERRED — never permanently dropped. The transaction returns a sentinel,
 * and the deferral runs outside it (a throw would abort the transaction and
 * roll back the pending marker). The event is retried by the trigger's
 * `retry: true` policy and, if the user doc never appears, is given up
 * explicitly and audibly after RELIABILITY_MISSING_USER_RETRY_MS.
 *
 * @param {admin.firestore.DocumentReference} orderRef
 * @param {'COLLECTED'|'NO_SHOW'} outcome
 * @return {Promise<boolean>} true when the event updated the summary
 */
async function processReliabilityEvent(orderRef, outcome) {
  const result = await db.runTransaction(async (transaction) => {
    const orderSnapshot = await transaction.get(orderRef);
    if (!orderSnapshot.exists) return false;
    const orderData = orderSnapshot.data();
    if (!orderData) return false;

    // The order must still be in the terminal state that triggered this
    // event (guards against a concurrent transition reverting it).
    const canonicalStatus =
      orderData.status === "COLLECTED" ? "collected" : orderData.status;
    if (outcome === "COLLECTED" && canonicalStatus !== "collected") {
      return false;
    }
    if (outcome === "NO_SHOW" && canonicalStatus !== "no_show") {
      return false;
    }
    // Idempotency: never count the same order twice.
    if (orderData.reliabilityProcessed === true) return false;

    const studentId = orderData.studentId || orderData.userId;
    if (!studentId) {
      console.warn("[PickupReliability] Order without studentId — skipping");
      return false;
    }

    const userRef = db.collection("users").doc(studentId);
    const userSnapshot = await transaction.get(userRef);
    if (!userSnapshot.exists) {
      // Defer, do NOT drop: the user doc may be created or restored later
      // (e.g. account restored after deletion, or a user doc written after
      // the order reached a terminal state). The order is NOT marked
      // reliabilityProcessed here, so a later retry can still count it.
      // deferReliabilityEvent re-reads order + user and writes its
      // pending/skip markers in its OWN transaction; only the retriable
      // throw happens after that transaction commits.
      return DEFER_RELIABILITY_EVENT;
    }

    // The recent-window timestamp is the order's persisted terminal outcome
    // time (collectedAt for COLLECTED, expiredAt for NO_SHOW), NOT the event
    // processing time — a delayed or redelivered event must not shift the
    // recent window. The trigger persists the terminal timestamp BEFORE
    // reliability processing (and the scheduled no-show processor writes
    // expiredAt in the same update that flips the status), so this re-read
    // normally finds it; the current-time fallback only guards a field that
    // is somehow still absent.
    const outcomeAt = outcome === "COLLECTED"
      ? orderData.collectedAt
      : orderData.expiredAt;
    const timestamp = outcomeAt instanceof admin.firestore.Timestamp
      ? outcomeAt
      : admin.firestore.Timestamp.now();
    const summary = recomputeReliability(
      userSnapshot.data().pickupReliability,
      outcome,
      orderRef.id,
      timestamp,
    );

    transaction.update(userRef, { pickupReliability: summary });
    transaction.update(orderRef, {
      reliabilityProcessed: true,
      // Immutable record of which outcome was counted ("COLLECTED" or
      // "NO_SHOW"), written atomically with the processed marker so a
      // redelivered event can never record a different outcome for the same
      // order.
      reliabilityOutcome: outcome,
      // Clear any stale deferral/skip markers when the event finally counts.
      reliabilityPending: admin.firestore.FieldValue.delete(),
      reliabilityPendingSince: admin.firestore.FieldValue.delete(),
      reliabilitySkippedReason: admin.firestore.FieldValue.delete(),
      reliabilitySkippedAt: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(
      `[PickupReliability] ${outcome} order ${orderRef.id} → ` +
      `score ${summary.reliabilityScore} (${summary.status})`
    );
    return true;
  });

  if (result === DEFER_RELIABILITY_EVENT) {
    return deferReliabilityEvent(orderRef);
  }
  return result;
}

/**
 * Defer a reliability event whose student user document is missing.
 *
 * The order re-read, the user re-read, and the pending/skip-marker writes
 * all run inside a single Firestore transaction. Before writing skip
 * metadata the transaction re-checks the re-read state and returns without
 * changes when the event was already counted (`reliabilityProcessed` true)
 * or the user document now exists — a concurrent count or a restored user
 * doc can never be overwritten by a stale skip.
 *
 * Otherwise it records an auditable pending marker (`reliabilityPending` +
 * `reliabilityPendingSince`) — WITHOUT setting `reliabilityProcessed` — and
 * throws a retriable error so the trigger's `retry: true` policy redelivers
 * the event. If the user doc never appears within
 * RELIABILITY_MISSING_USER_RETRY_MS, the engine gives up EXPLICITLY: it
 * records `reliabilitySkippedReason: 'MISSING_USER'` with a timestamp and
 * only then marks the order processed so redeliveries stop.
 *
 * @param {admin.firestore.DocumentReference} orderRef
 * @return {Promise<false>} false once the event is resolved (counted by a
 *   concurrent delivery, order gone, or given up after the window); throws
 *   a retriable 'deferred' error while the event remains pending.
 */
async function deferReliabilityEvent(orderRef) {
  const now = admin.firestore.Timestamp.now();
  const result = await db.runTransaction(async (transaction) => {
    const orderSnapshot = await transaction.get(orderRef);
    if (!orderSnapshot.exists) return "done";
    const orderData = orderSnapshot.data();
    if (!orderData) return "done";

    // Idempotency: if a concurrent delivery (or the scheduled reconciler)
    // already counted this order, stop without writing any marker —
    // duplicate events count once.
    if (orderData.reliabilityProcessed === true) return "done";

    const studentId = orderData.studentId || orderData.userId;
    if (typeof studentId !== "string" || studentId.length === 0) {
      // No user doc can be located — nothing meaningful to defer. Do not
      // write skip metadata for an unresolvable order.
      return "done";
    }
    const userSnapshot = await transaction.get(
      db.collection("users").doc(studentId),
    );

    // The user doc now exists, so the event is countable — do not write
    // pending or skip markers. Throw below so the redelivered event counts
    // it normally instead of dropping it.
    if (userSnapshot.exists) return "countNow";

    const pendingSince = orderData.reliabilityPendingSince;
    const pendingTimestamp = pendingSince instanceof admin.firestore.Timestamp
      ? pendingSince
      : null;

    if (
      pendingTimestamp != null &&
      now.toMillis() - pendingTimestamp.toMillis() >= RELIABILITY_MISSING_USER_RETRY_MS
    ) {
      // Explicit, auditable give-up after the retry window: record WHY and
      // WHEN the event was skipped, then mark it processed so the trigger
      // stops retrying forever. Guarded by the re-reads above (not already
      // processed, user still missing), so a concurrent count or a restored
      // user doc can never be overwritten by a stale skip.
      console.warn(
        `[PickupReliability] Missing user doc for order ${orderRef.id} ` +
        `beyond the retry window — recording explicit skip (MISSING_USER)`
      );
      // Note: reliabilityOutcome is intentionally NOT written here — the
      // event was skipped, not counted, so there is no outcome to record.
      // reliabilitySkippedReason/At disambiguate this from a counted event.
      transaction.update(orderRef, {
        reliabilityProcessed: true,
        reliabilitySkippedReason: "MISSING_USER",
        reliabilitySkippedAt: now,
        // The deferred state is resolved; drop the pending markers so the
        // scheduled reconciler does not pick this order up again.
        reliabilityPending: admin.firestore.FieldValue.delete(),
        reliabilityPendingSince: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return "skip";
    }

    if (pendingTimestamp == null) {
      console.warn(
        `[PickupReliability] Missing user doc for order ${orderRef.id} — ` +
        `deferring event for retry`
      );
      transaction.update(orderRef, {
        reliabilityPending: true,
        reliabilityPendingSince: now,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return "defer";
  });

  if (result === "defer" || result === "countNow") {
    // Retriable error: the trigger's retry: true policy redelivers the
    // event until the user doc appears (counted normally on a retry), the
    // retry window elapses (explicit MISSING_USER skip above), or the event
    // is already counted by a concurrent delivery. countNow keeps the
    // redelivery flowing so the next attempt counts the event — it must
    // never return false here, or the race-window event would be dropped.
    throw new Error(result === "countNow"
      ? `[PickupReliability] Order ${orderRef.id} deferral re-check — ` +
        `user doc now exists, redelivering to count — deferred`
      : `[PickupReliability] Missing user doc for order ${orderRef.id} — deferred`
    );
  }
  return false;
}

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 2: onOrderStatusChanged  (Firestore trigger)
// ════════════════════════════════════════════════════════════════════════════

// ── onOrderStatusChanged / onNewOrder helpers ─────────────────────────────────
//
// The trigger callbacks are split into small single-purpose helpers so they
// stay within the cognitive complexity budget while preserving every backfill,
// terminal-timestamp, reliability and notification behaviour.

/**
 * Run an idempotent order backfill (foodIds / cafes) with bounded retries.
 * @param {string} label — "foodIds" or "cafes" (used in log/error text)
 * @param {Function} backfillFn — the idempotent backfill call
 * @param {string} [logPrefix="[onOrderStatusChanged]"] — log/error prefix
 * @return {Promise<boolean>} false when the order no longer exists (nothing to
 *   do — the caller should return early), true when it completed or rethrew.
 */
async function runOrderBackfill(label, backfillFn, logPrefix = "[onOrderStatusChanged]") {
  try {
    await withRetry(backfillFn, {
      maxRetries: 3,
      baseDelayMs: 200,
      maxDelayMs: 2000,
      isPermanent: (err) => isNotFoundError(err), // order deleted mid-run
    });
    return true;
  } catch (err) {
    console.error(
      `${logPrefix} ${label} backfill failed: ${err.message}`
    );
    // NOT_FOUND means the order no longer exists — nothing left to
    // backfill and no status/notification work is meaningful for a
    // deleted order, so return early instead of retrying a permanent
    // failure.  Any other failure is rethrown so the event is not
    // acknowledged as successful.
    if (isNotFoundError(err)) {
      return false;
    }
    throw err;
  }
}

/**
 * Stamp an authoritative terminal timestamp (collectedAt / expiredAt) on the
 * order, guarded by a fresh re-read so a redelivered event cannot re-stamp
 * (drift) the persisted value. The get → update is intentionally a single
 * atomic write (not a read-modify-write): a concurrent same-event redelivery
 * could at worst overwrite the timestamp with another ~now value, which is
 * harmless because the reliability engine re-reads whichever value won.
 * @param {admin.firestore.DocumentReference} ref
 * @param {Object} data — the after snapshot for the field guard
 * @param {string} fieldName — "collectedAt" or "expiredAt"
 * @param {Object} extraFields — additional fields written with the timestamp
 * @param {string} logMessage
 */
async function stampTerminalTimestamp(ref, data, fieldName, extraFields, logMessage) {
  if (data[fieldName] == null) {
    const freshSnapshot = await ref.get();
    if (freshSnapshot.exists && freshSnapshot.data()[fieldName] == null) {
      await ref.update({
        [fieldName]: admin.firestore.Timestamp.now(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...extraFields,
      });
      console.log(logMessage);
    }
  }
}

/**
 * Handle a transition into READY: record the authoritative readyAt and the
 * distance-based pickup deadline, then notify the student.
 * @param {admin.firestore.DocumentReference} ref
 * @param {Object} afterData
 * @param {string} orderId
 */
async function handleOrderReady(ref, afterData, orderId) {
  if (afterData.readyAt != null) return;

  const now = admin.firestore.Timestamp.now();
  // Honor the order's stored (distance-based) pickup window when it is a
  // valid window (10–25 minutes, the range placeOrder validates); fall
  // back to the default for legacy orders that predate distance windows.
  const storedWindow = afterData.pickupWindowMinutes;
  const windowMinutes =
    Number.isInteger(storedWindow) &&
    storedWindow >= 10 &&
    storedWindow <= 25
      ? storedWindow
      : PICKUP_WINDOW_MINUTES;
  const deadline = new admin.firestore.Timestamp(
    now.seconds + windowMinutes * 60,
    now.nanoseconds,
  );

  await ref.update({
    readyAt: now,
    pickupDeadline: deadline,
    pickupWindowMinutes: windowMinutes,
    deadlineStatus: "ACTIVE",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(
    `[onOrderStatusChanged] Order marked READY. ` +
    `Pickup deadline: ${deadline.toDate().toISOString()}`,
  );

  const studentId = afterData.studentId;
  if (studentId) {
    try {
      await createNotification({
        recipientId: studentId,
        recipientRole: "student",
        type: "ORDER_READY",
        title: "Order Ready for Pickup",
        message: `Your order #${orderId} is ready! ` +
                 `Please collect it within ${windowMinutes} minutes.`,
        orderId,
        deepLink: `/orders/${orderId}`,
        eventId: notificationEventId("ORDER_READY", orderId),
        createdBy: "system",
      });
    } catch (notifErr) {
      console.error(
        `[onOrderStatusChanged] Failed to create ORDER_READY notification:`, notifErr
      );
    }
  }
}

/**
 * Handle a transition into COLLECTED: persist the authoritative collectedAt
 * (before reliability processing) and, for a genuine READY → COLLECTED
 * transition, count the pickup in the student's reliability summary.
 * @param {admin.firestore.DocumentReference} ref
 * @param {Object} afterData
 * @param {string} beforeStatus — canonicalised previous status
 */
async function handleOrderCollected(ref, afterData, beforeStatus) {
  // Persist the authoritative terminal timestamp BEFORE reliability
  // processing: the reliability engine's transaction re-reads the order
  // and uses the persisted collectedAt (never a fresh now) for the
  // recent-window history entry, so the history timestamp always equals
  // the order's authoritative collection time.
  await stampTerminalTimestamp(
    ref,
    afterData,
    "collectedAt",
    { deadlineStatus: "COLLECTED" },
    `[onOrderStatusChanged] Order marked COLLECTED.`
  );

  // Phase B.2 — terminal pickup outcome: update the student's
  // reliability summary. Only a genuine READY → COLLECTED transition
  // counts: an order that jumps straight to a terminal state without
  // ever being READY (an invalid transition per the rules) must never
  // affect reliability. Idempotency is enforced by the
  // reliabilityProcessed marker inside the transaction, never by this
  // branch. A transient failure is rethrown so Cloud Functions retries
  // the whole event — the marker makes the retry safe, and swallowing
  // it would permanently lose the event (orders are rarely updated
  // again after a terminal state).
  if (beforeStatus === "ready") {
    await processReliabilityEvent(ref, "COLLECTED");
  }
}

/**
 * Handle a transition into NO_SHOW (admin marks directly): persist the
 * authoritative expiredAt and, for a genuine READY → NO_SHOW transition,
 * count the missed pickup in the student's reliability summary.
 * @param {admin.firestore.DocumentReference} ref
 * @param {Object} afterData
 * @param {string} beforeStatus — canonicalised previous status
 */
async function handleOrderNoShow(ref, afterData, beforeStatus) {
  // Persist the authoritative terminal timestamp BEFORE reliability
  // processing (same reasoning as the COLLECTED branch): the engine's
  // history entry uses the persisted expiredAt, and a fresh-read guard
  // prevents a redelivered event from re-stamping it. The scheduled
  // processor already writes expiredAt in its update, so its event
  // snapshot carries it and this write is skipped.
  await stampTerminalTimestamp(
    ref,
    afterData,
    "expiredAt",
    {
      noShowProcessed: true,
      deadlineStatus: "EXPIRED",
      // Phase H — default food disposition on the manual NO_SHOW path:
      // UNRESOLVED until an authorized admin records the outcome (§3).
      // Only set when the field is genuinely absent so an already-recorded
      // disposition is never overwritten by this bookkeeping write.
      ...(afterData.foodDisposition == null
        ? { foodDisposition: "UNRESOLVED" }
        : {}),
    },
    `[onOrderStatusChanged] Order marked NO_SHOW.`
  );

  // Phase B.2 — terminal pickup outcome: update the student's
  // reliability summary (see the COLLECTED branch above for why the
  // timestamp is persisted first and why failures are rethrown).
  if (beforeStatus === "ready") {
    await processReliabilityEvent(ref, "NO_SHOW");
  }
}

exports.onOrderStatusChanged = onDocumentUpdated(
  {
    document: "orders/{orderId}",
    region: "us-central1",
    // Retry the whole event when a backfill rethrows a transient error,
    // so a failed backfill is not acknowledged as a successful event.
    retry: true,
  },
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();

    if (!beforeData || !afterData) return;

    const ref = event.data.after.ref;

    // Backfill `foodIds` on legacy orders (see helpers above) before any
    // review eligibility can be evaluated.  Runs on every order update —
    // including the admin's transition to COLLECTED — so legacy orders
    // become reviewable as soon as they are touched.
    //
    // A failed backfill must NOT be acknowledged as a successful event:
    // transient write failures are retried in-invocation (withRetry), and
    // if the backfill still fails the error is rethrown after logging so
    // Cloud Functions retries the whole event.  Retries are safe because
    // backfillOrderFoodIds is idempotent (no-op when foodIds is present,
    // with any value) and the ORDER_READY notification is deduplicated by
    // eventId in createNotification — no side effects are duplicated.
    if (!(await runOrderBackfill("foodIds", () => backfillOrderFoodIds(ref, afterData)))) {
      return;
    }

    // Backfill `cafes` (server-authoritative per-cafe scoping list) on
    // legacy orders touched by any update — the same idempotent pattern as
    // the foodIds backfill above.
    if (!(await runOrderBackfill("cafes", () => backfillOrderCafes(ref, afterData)))) {
      return;
    }

    if (beforeData.status === afterData.status) return;

    // Legacy admin writes may store uppercase 'COLLECTED'; canonicalise
    // before branching (mirrors canonicalOrderStatus in the rules).
    const status = afterData.status === "COLLECTED" ? "collected" : afterData.status;
    const beforeStatus =
      beforeData.status === "COLLECTED" ? "collected" : beforeData.status;

    // ── READY: record the authoritative readyAt + pickupDeadline ────
    if (status === "ready") {
      await handleOrderReady(ref, afterData, event.params.orderId);
      return;
    }

    // ── COLLECTED: record the authoritative collectedAt ─────────────
    if (status === "collected") {
      await handleOrderCollected(ref, afterData, beforeStatus);
      return;
    }

    // ── NO_SHOW: keep the state self-consistent when an admin marks an
    //    order no_show directly. The scheduled processor already writes
    //    these fields, so its updates make this branch a no-op.
    if (status === "no_show") {
      await handleOrderNoShow(ref, afterData, beforeStatus);
      return;
    }
  },
);

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 3: onNewOrder  (Firestore trigger — document created)
// ════════════════════════════════════════════════════════════════════════════

// ── onNewOrder helpers ────────────────────────────────────────────────────────
//
// The trigger is split into small single-purpose helpers so the onDocumentCreated
// callback stays within the cognitive complexity budget while preserving every
// backfill, cancellation-deadline correction and notification behaviour.

/**
 * Correct the order's cancellationDeadline to the authoritative value
 * (createdAt + CANCELLATION_WINDOW_MINUTES) when the stored value is missing
 * or differs. The client may send an estimated deadline so the acceptance
 * rules are enforced from the very first write (closing the admin-accept
 * race), but this correction overwrites it with the authoritative value so a
 * skewed device clock can never extend or shorten the window. A persistent
 * failure is rethrown so the event is not acknowledged as successful —
 * retries are safe because the backfills and pricing normalization are
 * idempotent and NEW_ORDER notifications are deduplicated by eventId.
 * @param {admin.firestore.DocumentReference} ref
 * @param {Object} orderData — the trigger snapshot
 * @param {string} orderId
 */
async function correctCancellationDeadline(ref, orderData, orderId) {
  if (!(orderData.createdAt instanceof admin.firestore.Timestamp)) return;

  const authoritativeDeadline = new admin.firestore.Timestamp(
    orderData.createdAt.seconds + CANCELLATION_WINDOW_MINUTES * 60,
    orderData.createdAt.nanoseconds,
  );
  const stored = orderData.cancellationDeadline;
  const needsCorrection =
    !(stored instanceof admin.firestore.Timestamp) ||
    stored.seconds !== authoritativeDeadline.seconds ||
    stored.nanoseconds !== authoritativeDeadline.nanoseconds;
  if (!needsCorrection) return;

  try {
    await withRetry(
      () => ref.update({
        cancellationDeadline: authoritativeDeadline,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }),
      {
        maxRetries: 2,
        baseDelayMs: 150,
        maxDelayMs: 1000,
      },
    );
    console.log(
      `[onNewOrder] Authoritative cancellationDeadline set for ${orderId}`
    );
  } catch (deadlineErr) {
    console.error(
      `[onNewOrder] Failed to correct cancellationDeadline:`, deadlineErr
    );
    throw deadlineErr;
  }
}

/**
 * Notify the admins serving the order's cafes about a new order. Per-cafe
 * scoping: an admin is notified only when their cafeName is in the order's
 * server-authoritative `cafes` list. Cafeless orders (nothing derivable, or
 * tagged with the UNASSIGNED sentinel) fall back to notifying every admin so
 * no order is ever left invisible. Failures are logged but never rethrown —
 * the Firestore notification doc is the source of truth and push delivery
 * happens separately in onNewNotification.
 * @param {Object} params
 * @param {string} params.orderId
 * @param {string} params.studentName
 * @param {number} params.totalAmount
 * @param {string[]} params.afterCafes — server-authoritative cafe scoping list
 */
async function notifyAdminsOfNewOrder({ orderId, studentName, totalAmount, afterCafes }) {
  try {
    const adminSnapshot = await db
        .collection("users")
        .where("role", "==", "admin")
        .where("accountStatus", "==", "ACTIVE")
        .get();

    if (adminSnapshot.empty) {
      console.log("[onNewOrder] No admin users found — skipping notifications");
      return;
    }

    const orderCafes = afterCafes.length > 0 ? afterCafes : null;
    const servingAdmins = orderCafes
      ? adminSnapshot.docs.filter((doc) => {
          const adminCafe = doc.data().cafeName;
          return typeof adminCafe === "string" &&
            orderCafes.includes(adminCafe);
        })
      : adminSnapshot.docs;

    if (servingAdmins.length === 0) {
      console.log(
        `[onNewOrder] No admin serves cafes of order — skipping notifications`
      );
      return;
    }

    console.log(`[onNewOrder] Notifying ${servingAdmins.length} admin(s)`);

    const adminIds = servingAdmins.map((doc) => doc.id);
    const notificationPromises = adminIds.map((adminId) => {
      return createNotification({
        recipientId: adminId,
        recipientRole: "admin",
        type: "NEW_ORDER",
        title: `New Order #${orderId}`,
        message: `${studentName} placed a new order worth ` +
                 `Tsh ${Math.round(totalAmount)}.`,
        orderId: orderId,
        eventId: `NEW_ORDER_${orderId}_${adminId}`,
        deepLink: "/orders",
        metadata: {
          studentName: studentName,
          totalAmount: totalAmount,
        },
        createdBy: "system",
      });
    });

    await Promise.allSettled(notificationPromises);
  } catch (err) {
    console.error(`[onNewOrder] Error:`, err);
  }
}

exports.onNewOrder = onDocumentCreated(
  {
    document: "orders/{orderId}",
    region: "us-central1",
    // Retry the whole event when the backfill rethrows a transient error,
    // so a failed backfill is not acknowledged as a successful event.
    retry: true,
  },  async (event) => {
    const orderData = event.data.data();
    if (!orderData) {
      console.log("[onNewOrder] No data for order — skipping");
      return;
    }

    // Backfill `foodIds` when an order was created without it (e.g. by a
    // legacy app build whose create payload predates the field).  Orders
    // from the current app already include the field, so this is a no-op.
    // A failed backfill must NOT be acknowledged as a successful event —
    // runOrderBackfill rethrows non-NOT_FOUND failures so Cloud Functions
    // retries the whole event.  Retries are safe because
    // backfillOrderFoodIds is idempotent (no-op when foodIds is present,
    // with any value) and NEW_ORDER notifications are deduplicated by
    // eventId in createNotification — no side effects are duplicated.
    if (!(await runOrderBackfill(
      "foodIds",
      () => backfillOrderFoodIds(event.data.ref, orderData),
      "[onNewOrder]",
    ))) {
      return; // order deleted mid-run (NOT_FOUND)
    }

    // Backfill `cafes` (server-authoritative per-cafe scoping list) when an
    // order was created without it (e.g. by a legacy app build).  Orders
    // from the current placeOrder callable already include the field, so
    // this is a no-op for them.  Same idempotent pattern as above.
    if (!(await runOrderBackfill(
      "cafes",
      () => backfillOrderCafes(event.data.ref, orderData),
      "[onNewOrder]",
    ))) {
      return; // order deleted mid-run (NOT_FOUND)
    }

    const studentName = orderData.userName || "A student";
    const orderId = event.params.orderId;

    // Server-authoritative per-cafe scoping list. Orders from the current
    // placeOrder callable carry the field. Legacy orders that the backfill
    // above just tagged are NOT reflected in the pre-write orderData, so
    // derive the cafes from the same items the backfill used — a legacy
    // order successfully scoped by the backfill must notify its cafe's
    // admin instead of falling back to every admin. An EMPTY `cafes` array
    // is treated as absent: it was written by the old `|| []` behaviour and
    // is repaired by the backfill (deriving from items), so it must not be
    // treated as a real scoping scope (which would notify zero admins). The
    // UNASSIGNED sentinel marks a genuinely cafeless order — such an order
    // falls back to notifying every admin.
    const rawOrderCafes =
      Array.isArray(orderData.cafes) && orderData.cafes.length > 0
        ? orderData.cafes
        : deriveOrderCafes(orderData.items);
    const afterCafes = Array.isArray(rawOrderCafes)
      ? rawOrderCafes.filter((c) => c !== UNASSIGNED_CAFE)
      : [];

    // Phase 15 — order financial integrity: correct any client-tampered
    // line-item prices and the order total against the authoritative
    // `food_items` docs. Returns the recomputed total when a corrective
    // write was performed (the pre-write orderData.price is stale), or the
    // originally-supplied total when pricing was already authoritative.
    // A transient failure rethrows so the event is retried — a tampered
    // order must be corrected, not acknowledged.
    const pricedTotal = await normalizeOrderPricing(
      event.data.ref, orderData
    );
    const totalAmount = pricedTotal != null
        ? pricedTotal
        : (orderData.price || orderData.totalAmount || 0);

    // ── Phase B: authoritative cancellation deadline ────────────────
    // cancellationDeadline = createdAt + 2 minutes, computed from the
    // trusted server timestamp (createdAt) — the authoritative value the
    // acceptance rules and the cancelOrder callable enforce.
    await correctCancellationDeadline(event.data.ref, orderData, orderId);

    console.log("[onNewOrder] New order received");

    await notifyAdminsOfNewOrder({
      orderId,
      studentName,
      totalAmount,
      afterCafes,
    });
  },
);

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 4: onNewNotification — FCM Push Delivery  (Firestore trigger)
// ════════════════════════════════════════════════════════════════════════════

/**
 * When a notification document is created in Firestore, send an FCM push
 * notification to the recipient's active devices.
 *
 * This is the central push delivery mechanism for Phase 8.
 * The Firestore notification is always created FIRST (source of truth),
 * then the push is sent asynchronously via this trigger.
 *
 * If push delivery fails, the notification remains in Firestore (no data loss).
 * Invalid tokens are deactivated; transient errors are logged but tokens kept.
 */
exports.onNewNotification = onDocumentCreated(
  {
    document: "notifications/{notificationId}",
    region: "us-central1",
  },
  async (event) => {
    const notifData = event.data.data();
    if (!notifData) {
      console.log("[onNewNotification] No data for notification — skipping");
      return;
    }

    const notificationId = event.params.notificationId;
    const recipientId = notifData.recipientId;
    const recipientRole = notifData.recipientRole;

    if (!recipientId || !recipientRole) {
      console.log(`[onNewNotification] Missing recipient info — skipping push`);
      return;
    }

    // ── Notification type-to-role allowlist ───────────────────────────
    // This maps each notification type to the role(s) that may receive it.
    // Admins receive only NEW_ORDER; student-only notifications are blocked
    // from routing to admins, and vice versa.
    const typeRoleAllowlist = {
      // Admin-only notifications
      NEW_ORDER: ["admin"],
      // Student-only notifications
      ORDER_ACCEPTED: ["student"],
      ORDER_PREPARING: ["student"],
      ORDER_READY: ["student"],
      ORDER_NO_SHOW: ["student"],
      ORDER_CANCELLED: ["student"],
      STRIKE_ISSUED: ["student"],
      STRIKE_REMOVED: ["student"],
      ACCOUNT_REACTIVATED: ["student"],
      ACCOUNT_SUSPENDED: ["student"],
      PICKUP_REMINDER: ["student"],
    };

    const allowedRoles = typeRoleAllowlist[notifData.type];
    if (!allowedRoles) {
      console.log(
        `[onNewNotification] Unknown type "${notifData.type}" — skipping push ` +
        `for ${recipientRole}`
      );
      return;
    }

    if (!allowedRoles.includes(recipientRole)) {
      console.log(
        `[onNewNotification] Role mismatch: ${notifData.type} not allowed for ` +
        `${recipientRole} — skipping push`
      );
      return;
    }

    console.log(
      `[onNewNotification] Sending push for ${notifData.type} to ${recipientRole}`
    );

    try {
      const result = await sendPushNotification({
        recipientId: recipientId,
        recipientRole: recipientRole,
        title: notifData.title || "CampusBite Update",
        body: notifData.message || "",
        deepLink: notifData.deepLink || null,
        notificationId: notificationId,
        type: notifData.type || "",
        orderId: notifData.orderId || null,
        eventId: notifData.eventId || null,
      });

      console.log(
        `[onNewNotification] Push delivery: ` +
        `${result.sent}/${result.total} sent, ` +
        `${result.failures.length} failure(s)`
      );
    } catch (err) {
      // Push failure must never affect the Firestore notification.
      console.error(
        `[onNewNotification] Push delivery error:`, err
      );
    }
  },
);

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 4.5: createAdminAccount  (Callable — existing admin only)
// ════════════════════════════════════════════════════════════════════════════

// Server-authoritative admin provisioning (no self-registration): only an
// existing, ACTIVE admin may create a new admin account. The client SDK
// cannot create another user's credentials while staying signed in, so the
// auth account AND the users/{uid} admin profile are created here with the
// Admin SDK (rules-bypassing). Self-registration stays blocked by the
// Firestore rules (validUserCreateRequest requires isAdmin()), and a brand
// new deployment bootstraps its first admin out-of-band (Admin SDK script —
// see README).

// ── createAdminAccount helpers ────────────────────────────────────────────────
//
// The callable is split into small single-purpose helpers so the onCall
// callback stays within the cognitive complexity budget while preserving
// every validation and rollback behaviour.

/**
 * Validate and normalize the createAdminAccount request payload.
 * @param {*} data — request.data
 * @return {{email: string, password: string, fullName: string,
 *   cafeName: string, phoneNumber: string}} the normalized fields
 */
function validateCreateAdminPayload(data) {
  if (data === null || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "Invalid request payload.");
  }
  const email = typeof data.email === "string" ? data.email.trim() : "";
  const password = typeof data.password === "string" ? data.password : "";
  const fullName = typeof data.fullName === "string" ? data.fullName.trim() : "";
  const cafeName = typeof data.cafeName === "string" ? data.cafeName.trim() : "";
  const phoneNumber =
    typeof data.phoneNumber === "string" ? data.phoneNumber.trim() : "";

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "A valid admin email is required.");
  }
  if (password.length < 6) {
    throw new HttpsError(
      "invalid-argument",
      "Password must be at least 6 characters."
    );
  }
  if (fullName.length === 0 || fullName.length > 100) {
    throw new HttpsError(
      "invalid-argument",
      "A full name (max 100 characters) is required."
    );
  }
  if (cafeName.length === 0 || cafeName.length > 100) {
    throw new HttpsError(
      "invalid-argument",
      "A cafe name (max 100 characters) is required."
    );
  }
  if (phoneNumber.length >= 20) {
    throw new HttpsError(
      "invalid-argument",
      "Phone number must be under 20 characters."
    );
  }
  return { email, password, fullName, cafeName, phoneNumber };
}

/**
 * Best-effort rollback of a partially-created admin: delete the auth account
 * and the users/{newUid} profile. Both deletions are best-effort — cleanup
 * failures are logged and swallowed so the original error propagates.
 * @param {string} newUid
 */
async function rollbackCreatedAdmin(newUid) {
  try {
    await admin.auth().deleteUser(newUid);
  } catch (cleanupErr) {
    console.error(`[createAdminAccount] Cleanup delete failed:`, cleanupErr);
  }
  try {
    await admin.firestore().collection("users").doc(newUid).delete();
  } catch (cleanupErr) {
    console.error(
      `[createAdminAccount] Profile cleanup delete failed:`, cleanupErr
    );
  }
}

exports.createAdminAccount = onCall(
  {
    authPolicy: "required",
    enforceAppCheck: true,
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to create an admin account."
      );
    }

    // ── Phase 15 — full admin authorization (mirrors deleteCloudinaryImage)
    // Role verification alone is not enough: the account must exist, carry
    // the admin role, and be ACTIVE (deny-by-default on accountStatus).
    const callerUid = request.auth.uid;
    const callerDoc = await admin
      .firestore().collection("users").doc(callerUid).get();
    const callerData = callerDoc.data();
    if (!callerDoc.exists || !callerData) {
      throw new HttpsError(
        "permission-denied",
        "Account not found. Please contact support."
      );
    }
    if (callerData.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only an existing admin can create admin accounts."
      );
    }
    if (callerData.accountStatus !== "ACTIVE") {
      throw new HttpsError(
        "permission-denied",
        "Your account is suspended and cannot create admin accounts."
      );
    }

    // ── Request validation ─────────────────────────────────────────────
    const { email, password, fullName, cafeName, phoneNumber } =
      validateCreateAdminPayload(request.data);

    // ── Create the auth account, then the admin profile ───────────────
    let newUid;
    try {
      const created = await admin.auth().createUser({
        email,
        password,
        emailVerified: false,
        displayName: fullName,
      });
      newUid = created.uid;
    } catch (err) {
      const code = err && err.code ? String(err.code) : "";
      if (code === "auth/email-already-in-use" || code === "auth/email-exists") {
        throw new HttpsError(
          "already-exists",
          "An admin account with this email already exists."
        );
      }
      console.error(`[createAdminAccount] Auth user creation failed:`, err);
      throw new HttpsError("internal", "Could not create the admin account.");
    }

    try {
      await admin.firestore().collection("users").doc(newUid).set({
        fullName,
        cafeName,
        email,
        phoneNumber: phoneNumber || null,
        role: "admin",
        accountStatus: "ACTIVE",
        strikePercentage: 0,
        strikeCount: 0,
        lastStrikeAt: null,
        lastPardonAt: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Immutable audit record of the privileged action (Phase 15 Part 12).
      await admin.firestore().collection("audit_logs").add({
        adminId: callerUid,
        action: "CREATE_ADMIN",
        reason: `Created admin account for ${email}`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      // Best-effort rollback: remove BOTH the auth account and the
      // users/{newUid} profile. The profile may already have been written
      // when a later step fails (e.g. the audit write), so without this a
      // dangling admin-profile document (no matching auth user) would
      // linger; deleting both lets the caller retry cleanly.
      console.error(`[createAdminAccount] Profile write failed:`, err);
      await rollbackCreatedAdmin(newUid);
      throw new HttpsError("internal", "Could not create the admin account.");
    }

    return { uid: newUid, email };
  },
);

// ════════════════════════════════════════════════════════════════════════════
// PHASE G — ADMIN INTERVENTION: excuseNoShow (Callable — cafe admin only)
// ════════════════════════════════════════════════════════════════════════════
//
// Authorized cafe admins can EXCUSE a specific NO_SHOW order (a correction
// to an event, never a strike/pardon system). The reliability engine stays
// authoritative: excusing only removes the event from the failure counts
// and recomputes score / status / restriction with the Phase B + Phase E
// formulas. The original order remains NO_SHOW — its history is never
// rewritten. No client can set reliabilityScore/restrictionLevel directly;
// the ONLY intervention path is this callable.

/** Predefined excuse reasons (AGENTS.md Phase G §7). */
const EXCUSE_REASONS = new Set([
  "Student reported emergency",
  "Cafe unable to fulfill order",
  "System/application issue",
  "Pickup information was incorrect",
  "Admin-approved exception",
  "Other",
]);

// ── excuseNoShow helpers ──────────────────────────────────────────────────────
//
// The callable is split into small single-purpose helpers so the onCall
// callback stays within the cognitive complexity budget while preserving
// every authorization, validation, eligibility, reliability and audit
// behaviour.

/**
 * Validate a callable request envelope: payload shape, only the allowed
 * keys, and a well-formed orderId.
 * @param {*} data — request.data
 * @param {Object} options
 * @param {string[]} options.allowedKeys — the keys this callable accepts
 * @param {string} options.message — error message when an unexpected key or
 *   an empty payload is supplied
 * @return {Object} the validated payload
 */
function assertValidEnvelope(data, { allowedKeys, message }) {
  if (
    data === null ||
    typeof data !== "object" ||
    Array.isArray(data) ||
    JSON.stringify(data).length > 4096
  ) {
    throw new HttpsError("invalid-argument", "Invalid request payload.");
  }
  const envelopeKeys = Object.keys(data);
  const validKeys = envelopeKeys.filter((k) => allowedKeys.includes(k));
  if (validKeys.length !== envelopeKeys.length || envelopeKeys.length === 0) {
    throw new HttpsError("invalid-argument", message);
  }

  const { orderId } = data;
  if (
    !orderId ||
    typeof orderId !== "string" ||
    orderId.length === 0 ||
    orderId.length > 128 ||
    !/^[A-Za-z0-9_-]+$/.test(orderId)
  ) {
    throw new HttpsError("invalid-argument", "orderId is invalid.");
  }
  return data;
}

/**
 * Validate the excuse reason against the predefined choices (AGENTS.md §7).
 * @param {*} reason
 * @return {string} the validated reason
 */
function validateExcuseReason(reason) {
  if (typeof reason === "string" && EXCUSE_REASONS.has(reason)) {
    return reason;
  }
  throw new HttpsError(
    "invalid-argument",
    "reason must be one of the predefined excuse reasons."
  );
}

/**
 * Normalize the optional admin note (trimmed, max 200 chars, no
 * HTML/scripts/URLs — AGENTS.md §8) and enforce the required-note rule when
 * [requiresNote] is set (§7, §11). The rules language cannot express these
 * checks, so the callable enforces them server-side before anything is
 * written.
 * @param {*} note — the raw note field
 * @param {Object} [options]
 * @param {boolean} [options.requiresNote] — when true, a non-empty note is
 *   mandatory (default false)
 * @param {string} [options.requiredMessage] — error message for the missing
 *   note case
 * @return {string|null} the trimmed note, or null when absent
 */
function normalizeOptionalNote(
  note,
  { requiresNote = false, requiredMessage = "" } = {}
) {
  let normalized = null;
  if (note !== undefined && note !== null) {
    if (typeof note !== "string") {
      throw new HttpsError("invalid-argument", "note is invalid.");
    }
    const trimmed = note.trim();
    if (trimmed.length > 200) {
      throw new HttpsError(
        "invalid-argument",
        "note must be 200 characters or fewer."
      );
    }
    if (
      /<[a-z][^>]*>/i.test(trimmed) ||
      /https?:\/\//i.test(trimmed)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "note cannot contain HTML, scripts, or URLs."
      );
    }
    normalized = trimmed;
  }
  if (requiresNote && !normalized) {
    throw new HttpsError("invalid-argument", requiredMessage);
  }
  return normalized;
}

/**
 * Cafe-scope authorization (§34): the caller's cafeName must appear in the
 * order's server-authoritative `cafes` list. Only an order explicitly tagged
 * with the UNASSIGNED sentinel (genuinely cafeless) is served by any active
 * admin, mirroring the adminServesOrder() rules gate. An absent/empty
 * `cafes` value is unscoped legacy data — not cafeless — and is denied until
 * the backfill normalizes it.
 * @param {string} callerCafeName
 * @param {Object} orderData
 */
function assertAdminServesOrder(callerCafeName, orderData) {
  const orderCafes = Array.isArray(orderData.cafes)
    ? orderData.cafes.filter((c) => typeof c === "string")
    : [];
  const isCafelessOrder =
    orderCafes.length > 0 &&
    orderCafes.every((c) => c === UNASSIGNED_CAFE);
  if (
    !isCafelessOrder &&
    (callerCafeName.length === 0 ||
      !orderCafes.includes(callerCafeName))
  ) {
    throw new HttpsError(
      "permission-denied",
      "You are not authorized to manage orders for this cafe."
    );
  }
}

/**
 * Run the excuse transaction body: caller authorization, eligibility,
 * reliability correction, order excuse fields, the immutable audit record,
 * and the deterministic notification outbox event — all committed in ONE
 * transaction (§16-§18).
 * @param {admin.firestore.Transaction} transaction
 * @param {Object} params
 * @param {admin.firestore.DocumentReference} params.orderRef
 * @param {string} params.callerUid
 * @param {string} params.excuseReason
 * @param {string|null} params.excuseNote
 */
async function runExcuseTransaction(transaction, {
  orderRef, callerUid, excuseReason, excuseNote,
}) {
  // ── Caller authorization read INSIDE the transaction (mirrors
  //    setFoodDisposition): the caller document is re-read with the
  //    transaction, so existence / role / ACTIVE / cafe checks are atomic
  //    with the excuse write. If the caller changes concurrently
  //    (suspension, role change, cafe reassignment), Firestore aborts the
  //    transaction and the retry re-reads the fresh caller state.
  const callerSnapshot = await transaction.get(
    db.collection("users").doc(callerUid)
  );
  const callerData = callerSnapshot.data();
  if (!callerSnapshot.exists || !callerData) {
    throw new HttpsError(
      "permission-denied",
      "Account not found. Please contact support."
    );
  }
  if (callerData.role !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Only authorized cafe administrators can excuse a no-show."
    );
  }
  if (callerData.accountStatus !== "ACTIVE") {
    throw new HttpsError(
      "permission-denied",
      "Your account is suspended and cannot excuse a no-show."
    );
  }
  const callerCafeName =
    typeof callerData.cafeName === "string"
      ? callerData.cafeName.trim()
      : "";

  const orderSnapshot = await transaction.get(orderRef);
  if (!orderSnapshot.exists) {
    throw new HttpsError("not-found", "Order not found.");
  }
  const orderData = orderSnapshot.data();

  assertAdminServesOrder(callerCafeName, orderData);

  // ── Eligibility (§6): only NO_SHOW with a recorded noShowAt,
  //    and never already excused (§17).
  const canonicalStatus =
    orderData.status === "COLLECTED" ? "collected" : orderData.status;
  if (canonicalStatus !== "no_show") {
    throw new HttpsError(
      "failed-precondition",
      "Only no-show orders can be excused."
    );
  }
  if (!(orderData.noShowAt instanceof admin.firestore.Timestamp)) {
    throw new HttpsError(
      "failed-precondition",
      "This order has no recorded no-show time and cannot be excused."
    );
  }
  if (orderData.noShowExcused === true) {
    // ALREADY_EXCUSED — safe business result (§17). The marker is
    // read inside this transaction, so a concurrent excuse that
    // committed first is seen here and reported; the loser never
    // writes a duplicate correction, audit record, or notification.
    throw new HttpsError(
      "failed-precondition",
      "This no-show has already been excused."
    );
  }

  const now = admin.firestore.Timestamp.now();
  const studentId = orderData.studentId || orderData.userId;

  // ── Reliability correction (§11-§15): only when the no-show was
  //    actually counted by the engine. The summary correction and the
  //    order marker commit atomically here.
  if (
    typeof studentId === "string" &&
    studentId.length > 0 &&
    orderData.reliabilityProcessed === true &&
    orderData.reliabilityOutcome === "NO_SHOW"
  ) {
    const userRef = db.collection("users").doc(studentId);
    const userSnapshot = await transaction.get(userRef);
    if (userSnapshot.exists) {
      const corrected = recomputeReliabilityAfterExcuse(
        userSnapshot.data().pickupReliability,
        orderRef.id,
        now,
      );
      transaction.update(userRef, { pickupReliability: corrected });
    }
  }

  transaction.update(orderRef, {
    // The original NO_SHOW data is preserved; the excuse is additive.
    noShowExcused: true,
    excusedAt: now,
    excusedBy: callerUid,
    excuseReason,
    excuseNote,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // ── Immutable audit record (§22-§23). Deterministic doc ID so a
  //    concurrent duplicate can never append twice.
  transaction.set(
    db.collection("audit_logs").doc(`NO_SHOW_EXCUSED_${orderRef.id}`),
    {
      action: "NO_SHOW_EXCUSED",
      adminId: callerUid,
      orderId: orderRef.id,
      studentId: studentId || null,
      cafeId: callerCafeName,
      reason: excuseReason,
      note: excuseNote,
      timestamp: now,
    },
  );

  // ── Notification outbox event (§16, §26): the deterministic
  //    document keyed `NO_SHOW_EXCUSED_{orderId}` commits IN THE SAME
  //    transaction as the order state, reliability correction, and
  //    audit record. FCM push delivery is never performed here — it is
  //    handled exclusively by the onNewNotification trigger (an
  //    idempotent post-commit worker), which fires only after this
  //    document commits. If the transaction aborts, none of the six
  //    records are committed, so a failed intervention never leaves a
  //    stale outbox event or a student notification behind. The
  //    ALREADY_EXCUSED read above runs in this same transaction, so a
  //    concurrent duplicate aborts before writing a second outbox
  //    event.
  if (typeof studentId === "string" && studentId.length > 0) {
    const notifEventId = notificationEventId("NO_SHOW_EXCUSED", orderRef.id);
    transaction.set(
      db.collection("notifications").doc(notifEventId),
      {
        recipientId: studentId,
        recipientRole: "student",
        type: "NO_SHOW_EXCUSED",
        title: "Missed pickup excused",
        message: `An administrator reviewed Order #${orderRef.id} and excused ` +
          `the missed pickup. It will not affect your pickup reliability.`,
        orderId: orderRef.id,
        eventId: notifEventId,
        deepLink: null,
        metadata: null,
        read: false,
        readAt: null,
        deleted: false,
        deletedAt: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: "system",
      },
    );
  }
}

/**
 * Excuse a no-show order (Phase G).
 *
 * Backend-enforced authorization (AGENTS.md §2, §34): the caller must be an
 * authenticated, ACTIVE admin whose cafeName appears in the order's
 * server-authoritative `cafes` list. Cross-cafe excuses are denied. The
 * student ID is DERIVED from the order document, never accepted from the
 * client (§29).
 *
 * Atomicity & idempotency (§16-§18): the eligibility check, the order
 * excuse fields, the reliability summary correction, and the immutable
 * audit record are committed in ONE Firestore transaction. The audit doc
 * uses a deterministic ID derived from the order, and the
 * `noShowExcused` marker is checked + written in the same transaction, so
 * concurrent or duplicate excuses can never succeed twice (Firestore
    * aborts the loser, and its re-read sees the marker and reports
    * already-excused). The student notification document is written IN THE
    * SAME transaction under a deterministic eventId, so a failed
    * intervention never notifies and retries never duplicate (§25-§26).
    * FCM delivery happens post-commit in the onNewNotification trigger
 */
exports.excuseNoShow = onCall(
  {
    authPolicy: "required",
    enforceAppCheck: true,
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to excuse a no-show."
      );
    }

    const callerUid = request.auth.uid;

    // ── Request envelope validation ──────────────────────────────────
    const { orderId, reason, note } = assertValidEnvelope(request.data, {
      allowedKeys: ["orderId", "reason", "note"],
      message:
        "Request payload must contain only orderId, reason, and an optional note.",
    });
    const excuseReason = validateExcuseReason(reason);
    const excuseNote = normalizeOptionalNote(note, {
      requiresNote: excuseReason === "Other",
      requiredMessage: "A note is required when the reason is Other.",
    });

    const orderRef = db.collection("orders").doc(orderId);

    try {
      await db.runTransaction((transaction) =>
        runExcuseTransaction(transaction, {
          orderRef,
          callerUid,
          excuseReason,
          excuseNote,
        }),
      );

      // FCM delivery is handled by the onNewNotification trigger after this
      // transaction commits (post-commit worker). Nothing further is needed.
      console.log(
        `[OrderLifecycle] Order ${orderId} no-show excused (reason: ${excuseReason})`
      );
      return { success: true, orderId };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[excuseNoShow] Error:", err);
      throw new HttpsError(
        "internal",
        "Could not excuse the no-show. Please try again."
      );
    }
  },
);

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION: reactivateStudent  (Callable — admin only)
// ════════════════════════════════════════════════════════════════════════════
//
// Reactivates a genuinely SUSPENDED student account. The account-status flip
// and the immutable audit record commit in ONE Firestore transaction; the
// student notification is created after commit (eventId-deduped). Actor
// identity (adminId) and timestamp are derived SERVER-SIDE from the
// authenticated caller — never accepted from the client — because
// audit_logs are backend-only (AGENTS.md §23): Firestore rules deny all
// direct client creates on the collection.

exports.reactivateStudent = onCall(
  {
    authPolicy: "required",
    enforceAppCheck: true,
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to reactivate a student."
      );
    }

    // ── Admin authorization (mirrors createAdminAccount / excuseNoShow) ─
    const callerUid = request.auth.uid;
    const callerDoc = await admin
      .firestore().collection("users").doc(callerUid).get();
    const callerData = callerDoc.data();
    if (!callerDoc.exists || !callerData) {
      throw new HttpsError(
        "permission-denied",
        "Account not found. Please contact support."
      );
    }
    if (callerData.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only authorized cafe administrators can reactivate students."
      );
    }
    if (callerData.accountStatus !== "ACTIVE") {
      throw new HttpsError(
        "permission-denied",
        "Your account is suspended and cannot reactivate students."
      );
    }

    // ── Request validation ─────────────────────────────────────────────
    const data = request.data;
    if (data === null || typeof data !== "object" || Array.isArray(data)) {
      throw new HttpsError("invalid-argument", "Invalid request payload.");
    }
    const studentId = data.studentId;
    const reason = typeof data.reason === "string" ? data.reason.trim() : "";
    if (
      typeof studentId !== "string" ||
      studentId.length === 0 ||
      studentId.length > 128
    ) {
      throw new HttpsError("invalid-argument", "studentId is invalid.");
    }
    if (reason.length > 500) {
      throw new HttpsError(
        "invalid-argument",
        "reason must be 500 characters or fewer."
      );
    }

    const studentRef = db.collection("users").doc(studentId);

    try {
      await db.runTransaction(async (transaction) => {
        // Read the target through the transaction so the SUSPENDED check is
        // atomic with the ACTIVE write — no TOCTOU gap, and a concurrent
        // duplicate reactivation re-reads ACTIVE and aborts.
        const studentSnapshot = await transaction.get(studentRef);
        if (!studentSnapshot.exists) {
          throw new HttpsError(
            "not-found",
            "Student account not found."
          );
        }
        if (studentSnapshot.data().accountStatus !== "SUSPENDED") {
          throw new HttpsError(
            "failed-precondition",
            "Only genuinely suspended accounts can be reactivated."
          );
        }

        transaction.update(studentRef, {
          accountStatus: "ACTIVE",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Immutable audit record (§22-§23) — server-derived identity and
        // timestamp. Auto-ID: a student can be re-suspended and reactivated
        // again later, so each reactivation is its own record (the
        // SUSPENDED re-check above prevents duplicate concurrent records).
        transaction.set(db.collection("audit_logs").doc(), {
          action: "REACTIVATE",
          studentId,
          adminId: callerUid,
          reason: reason || "Account reactivated by admin",
          timestamp: admin.firestore.Timestamp.now(),
        });
      });

      // ── Student notification: created ONLY after the transaction
      //    committed — a failed reactivation never notifies, and the
      //    eventId dedup prevents duplicate notifications on retry.
      try {
        await createNotification({
          recipientId: studentId,
          recipientRole: "student",
          type: "ACCOUNT_REACTIVATED",
          title: "Account Reactivated",
          message: "Your account has been reactivated by an admin. " +
            "You can now place orders again.",
          eventId: notificationEventId("ACCOUNT_REACTIVATED", studentId),
          createdBy: "system",
        });
      } catch (notifErr) {
        // Notification failure must never fail the reactivation.
        console.error(
          `[reactivateStudent] Notification failed for ${studentId}:`, notifErr
        );
      }

      console.log(
        `[OrderLifecycle] Student ${studentId} reactivated by ${callerUid}`
      );
      return { success: true };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[reactivateStudent] Error:", err);
      throw new HttpsError(
        "internal",
        "Could not reactivate the account. Please try again."
      );
    }
  },
);

// ════════════════════════════════════════════════════════════════════════════
// PHASE H — CAFE FOOD WASTE MANAGEMENT: setFoodDisposition
// (Callable — cafe admin only)
// ════════════════════════════════════════════════════════════════════════════
//
// Authorized cafe admins record what happened to the prepared food of a
// NO_SHOW order. The order REMAINS NO_SHOW — disposition is a separate
// operational property that never changes order status or the student's
// reliability (AGENTS.md Phase H §1, §20-§21).
//
// Backend-enforced authorization (§7): the caller must be an authenticated,
// ACTIVE admin whose cafeName appears in the order's server-authoritative
// `cafes` list (mirrors excuseNoShow). studentId and cafeId are DERIVED from
// the order document, never accepted from the client (§17). Only NO_SHOW
// orders are eligible (§4); UNRESOLVED is the default state, never an
// admin-chosen target (§3).
//
// Atomicity & idempotency (§15-§16): the eligibility check, the order
// disposition fields, and the immutable audit record commit in ONE Firestore
// transaction. If currentDisposition == requestedDisposition the operation
// returns alreadyRecorded with NO writes, so repeated submissions never
// create duplicate audit records. A disposition correction (DONATED →
// DISPOSED, §12) appends a NEW audit record while the order reflects the
// latest value.

exports.setFoodDisposition = onCall(
  {
    authPolicy: "required",
    enforceAppCheck: true,
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to record a food disposition."
      );
    }

    // The caller's identity comes from the verified ID token. The caller
    // DOCUMENT (role / ACTIVE status / cafe scope) is re-read INSIDE the
    // transaction immediately before the write, so authorization is atomic
    // with the disposition update: a concurrent suspension, role change, or
    // cafe reassignment aborts the transaction and the retry re-reads the
    // fresh caller state instead of slipping a stale authorization through
    // (AGENTS.md §7 — never trust a pre-transaction snapshot).
    const callerUid = request.auth.uid;

    // ── Request envelope validation ─────────────────────────────────
    const { orderId, disposition, note } = assertValidEnvelope(
      request.data,
      {
        allowedKeys: ["orderId", "disposition", "note"],
        message:
          "Request payload must contain only orderId, disposition, and an optional note.",
      },
    );

    // Controlled disposition only (§2) — no free-form values.
    if (!FOOD_DISPOSITIONS.includes(disposition)) {
      throw new HttpsError(
        "invalid-argument",
        "disposition must be one of the predefined food dispositions."
      );
    }
    // UNRESOLVED is the default state written by the no-show engine, never
    // an admin-chosen target (§3).
    if (disposition === "UNRESOLVED") {
      throw new HttpsError(
        "invalid-argument",
        "Choose an outcome for the food; UNRESOLVED is the default state."
      );
    }

    // Optional admin note: trimmed, max 200 chars, no HTML/scripts/URLs
    // (§11 — the note is optional for every disposition, including OTHER;
    // only the excuse flow's "Other" reason requires one). The rules
    // language cannot express this, so the callable enforces it server-side
    // before anything is written.
    const dispositionNote = normalizeOptionalNote(note);

    const orderRef = db.collection("orders").doc(orderId);
    const callerRef = db.collection("users").doc(callerUid);

    try {
      let alreadyRecorded = false;
      await db.runTransaction(async (transaction) => {
        // Reset on every attempt so a transaction retry never inherits the
        // previous attempt's flag (the same pattern as the notification
        // repository's created flag).
        alreadyRecorded = false;

        // ── Caller authorization read INSIDE the transaction (§7): the
        //    caller document is re-read with the transaction, so the
        //    existence / role / ACTIVE / cafe checks below are atomic with
        //    the write. If the caller document changes concurrently
        //    (suspension, role change, cafe reassignment), Firestore aborts
        //    the transaction and the retry re-reads the fresh caller state.
        const callerSnapshot = await transaction.get(callerRef);
        const callerData = callerSnapshot.data();
        if (!callerSnapshot.exists || !callerData) {
          throw new HttpsError(
            "permission-denied",
            "Account not found. Please contact support."
          );
        }
        if (callerData.role !== "admin") {
          throw new HttpsError(
            "permission-denied",
            "Only authorized cafe administrators can record a food disposition."
          );
        }
        if (callerData.accountStatus !== "ACTIVE") {
          throw new HttpsError(
            "permission-denied",
            "Your account is suspended and cannot record a food disposition."
          );
        }
        const callerCafeName =
          typeof callerData.cafeName === "string"
            ? callerData.cafeName.trim()
            : "";

        const orderSnapshot = await transaction.get(orderRef);
        if (!orderSnapshot.exists) {
          throw new HttpsError("not-found", "Order not found.");
        }
        const orderData = orderSnapshot.data();

        // ── Cafe authorization (§7): shared with the excuse flow — the
        //    caller's cafeName must appear in the order's
        //    server-authoritative cafes list, derived from the
        //    transaction-fresh caller and order data. UNASSIGNED sentinel
        //    = genuinely cafeless (any active admin); absent/empty `cafes`
        //    is unscoped legacy data and is denied.
        assertAdminServesOrder(callerCafeName, orderData);

        // ── Eligibility (§4): only NO_SHOW orders may receive a food
        //    disposition. PENDING/ACCEPTED/PREPARING/READY/COLLECTED/
        //    CANCELLED/REJECTED are all rejected.
        const canonicalStatus =
          orderData.status === "COLLECTED" ? "collected" : orderData.status;
        if (canonicalStatus !== "no_show") {
          throw new HttpsError(
            "failed-precondition",
            "Only no-show orders can have a food disposition."
          );
        }

        // ── Idempotency (§16): same disposition submitted twice → no
        //    writes, no duplicate audit record. Read inside the transaction,
        //    so a concurrent duplicate that committed first is seen here.
        if (orderData.foodDisposition === disposition) {
          alreadyRecorded = true;
          return;
        }

        const now = admin.firestore.Timestamp.now();
        const studentId = orderData.studentId || orderData.userId;

        // ── One order update (§19): compact disposition record on the
        //    order. The note always describes the CURRENT disposition: when
        //    the admin supplies one it is written, otherwise a stale note
        //    from the previous disposition is cleared so the order can never
        //    display a note that contradicts the recorded outcome (e.g.
        //    "Disposed" + "Donated to support staff"). The prior note
        //    remains in the immutable audit trail.
        transaction.update(orderRef, {
          foodDisposition: disposition,
          foodDispositionAt: now,
          foodDispositionBy: callerUid,
          foodDispositionNote: dispositionNote !== null
            ? dispositionNote
            : admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // ── Immutable audit record (§13-§14). Auto-ID: dispositions can be
        //    corrected (DONATED → DISPOSED, §12), so each change is its own
        //    append-only record; the idempotency check above guarantees no
        //    duplicate record when the disposition is unchanged.
        transaction.set(db.collection("audit_logs").doc(), {
          action: "FOOD_DISPOSITION",
          orderId: orderRef.id,
          studentId: studentId || null,
          // The acting admin's cafe name (may be empty for a genuinely
          // cafeless order served by any admin) — adminCanReadAudit() treats
          // a cafeless record (empty/missing cafeId) as readable by any
          // admin, mirroring adminServesOrder(). Never null: a null cafeId
          // would make the record's read rule evaluate to false for everyone.
          cafeId: callerCafeName,
          adminId: callerUid,
          previousDisposition: orderData.foodDisposition || "UNRESOLVED",
          newDisposition: disposition,
          note: dispositionNote,
          timestamp: now,
        });
      });

      if (alreadyRecorded) {
        console.log(
          `[FoodDisposition] Order ${orderId} disposition unchanged ` +
          `(${disposition}) — already recorded`
        );
        return { success: true, alreadyRecorded: true, orderId };
      }

      console.log(
        `[FoodDisposition] Order ${orderId} disposition recorded: ${disposition}`
      );
      return { success: true, alreadyRecorded: false, orderId };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[setFoodDisposition] Error:", err);
      throw new HttpsError(
        "internal",
        "Could not record the food disposition. Please try again."
      );
    }
  },
);

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 5: deleteCloudinaryImage  (Callable — admin only)
// ════════════════════════════════════════════════════════════════════════════

const CLOUDINARY_CLOUD_NAME = defineSecret("CLOUDINARY_CLOUD_NAME");
const CLOUDINARY_API_KEY = defineSecret("CLOUDINARY_API_KEY");
const CLOUDINARY_API_SECRET = defineSecret("CLOUDINARY_API_SECRET");

exports.deleteCloudinaryImage = onCall(
  {
    authPolicy: "required",
    // Phase 15 — App Check: reject callers that cannot present a valid App
    // Check attestation token (Play Integrity on Android release builds).
    enforceAppCheck: true,
    secrets: [CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET],
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to delete images."
      );
    }

    // ── Phase 15 — full admin authorization ───────────────────────────
    // Role verification alone is not enough: the admin account must also
    // exist, be active, and not be suspended. This mirrors the "Admin
    // Authorization" checklist (Part 4).
    const uid = request.auth.uid;
    const userDoc = await admin.firestore().collection("users").doc(uid).get();
    const userData = userDoc.data();

    if (!userDoc.exists || !userData) {
      throw new HttpsError(
        "permission-denied",
        "Account not found. Please contact support."
      );
    }

    if (userData.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only admins can delete images."
      );
    }

    // ── Phase 15 — account status and strike validation ───────────────
    // accountStatus must be exactly "ACTIVE" — deny-by-default: a missing or
    // malformed value is rejected, never defaulted. strikeCount must be a
    // non-negative integer below 2 (a missing field means 0, matching the
    // rules); non-integer, NaN, or negative values are denied rather than
    // coerced — a NaN would otherwise bypass the suspension check because
    // `NaN >= 2` evaluates to false.
    const accountStatus = userData.accountStatus;
    const rawStrikeCount = userData.strikeCount;
    const strikeCount = rawStrikeCount === undefined ? 0 : rawStrikeCount;
    if (
      accountStatus !== "ACTIVE" ||
      !Number.isInteger(strikeCount) ||
      strikeCount < 0 ||
      strikeCount >= 2
    ) {
      throw new HttpsError(
        "permission-denied",
        "This account is suspended and cannot perform admin actions."
      );
    }

    // ── Phase 15 — request envelope validation ───────────────────────
    // request.data must be a non-null, non-array object containing exactly
    // the `publicId` field, within a bounded payload size. Validating the
    // envelope before destructuring means a null/malformed payload surfaces
    // as a clean HttpsError instead of a native TypeError that would bubble
    // up as a generic internal error (Part 5: reject malformed requests).
    const data = request.data;
    if (
      data === null ||
      typeof data !== "object" ||
      Array.isArray(data) ||
      JSON.stringify(data).length > 4096
    ) {
      throw new HttpsError("invalid-argument", "Invalid request payload.");
    }

    const envelopeKeys = Object.keys(data);
    if (envelopeKeys.length !== 1 || envelopeKeys[0] !== "publicId") {
      throw new HttpsError(
        "invalid-argument",
        "Request payload must contain exactly the publicId field."
      );
    }

    // ── Phase 15 — input validation ──────────────────────────────────
    // publicId must be a non-empty printable-ASCII string of at most 512
    // characters and must not contain a `..` sequence. The denylist rejects
    // control characters and path-traversal attempts (../) while remaining
    // permissive enough for Cloudinary IDs derived from filenames (which
    // may include spaces, '+', '@', '.', etc. after sanitization).
    const { publicId } = data;
    if (
      !publicId ||
      typeof publicId !== "string" ||
      publicId.length === 0 ||
      publicId.length > 512 ||
      publicId.includes("..") ||
      !/^[\x20-\x7E]+$/.test(publicId)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "publicId is invalid."
      );
    }

    const cloudName = CLOUDINARY_CLOUD_NAME.value();
    const apiKey = CLOUDINARY_API_KEY.value();
    const apiSecret = CLOUDINARY_API_SECRET.value();

    const url = `https://api.cloudinary.com/v1_1/${cloudName}/image/destroy`;
    const authString = `${apiKey}:${apiSecret}`;
    const authHeader = `Basic ${Buffer.from(authString).toString("base64")}`;

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: authHeader,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: `public_id=${encodeURIComponent(publicId)}`,
      });

      const result = await response.json();

      if (result.result === "ok") {
        await admin.firestore().collection("audit_logs").add({
          action: "cloudinary_image_deleted",
          publicId: publicId,
          deletedBy: uid,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        return { success: true };
      } else {
        throw new HttpsError(
          "internal",
          `Cloudinary deletion failed: ${result.error?.message || "Unknown error"}`
        );
      }
    } catch (error) {
      console.error("Error deleting Cloudinary image:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError(
        "internal",
        `Failed to delete image: ${error.message}`
      );
    }
  }
);

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 6: cleanupDeletedNotifications  (Scheduled — every 24 hours)
// ════════════════════════════════════════════════════════════════════════════

exports.cleanupDeletedNotifications = functions
    .runWith({
      memory: "128MB",
      timeoutSeconds: 120,
    })
    .pubsub
    .schedule("every 24 hours")
    .onRun(async (context) => {
      console.log("[CleanupNotifications] Scheduled cleanup started...");

      const cutoff = new Date();
      cutoff.setDate(cutoff.getDate() - 180);

      let deletedCount = 0;
      let errorCount = 0;

      try {
        const oldNotifications = await db
            .collection("notifications")
            .where("deleted", "==", true)
            .where("deletedAt", "<=", cutoff)
            .get();

        console.log(
          `[CleanupNotifications] Found ${oldNotifications.size} old deleted notification(s)`
        );

        let batch = db.batch();
        let batchSize = 0;

        for (const doc of oldNotifications.docs) {
          batch.delete(doc.ref);
          batchSize++;
          deletedCount++;

          if (batchSize >= 500) {
            await batch.commit();
            batch = db.batch();
            batchSize = 0;
          }
        }

        if (batchSize > 0) {
          await batch.commit();
        }
      } catch (err) {
        errorCount++;
        console.error("[CleanupNotifications] Error:", err);
      }

      console.log(
        `[CleanupNotifications] Cleanup complete: ${deletedCount} deleted, ${errorCount} errors`
      );

      return null;
    });

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 7: cleanupInactiveTokens  (Scheduled — weekly)
// ════════════════════════════════════════════════════════════════════════════

/**
 * Weekly cleanup of stale device tokens.
 *
 * Removes:
 * 1. Inactive tokens that have been inactive for more than 90 days.
 * 2. Inactive tokens with a deactivationReason (permanently invalid).
 * 3. Orphaned active tokens with no update in 180+ days — safety net for
 *    the migration from {userId}_{platform} doc IDs to auto-generated IDs.
 *
 * Phase 8: Token lifecycle management.
 */
exports.cleanupInactiveTokens = functions
    .runWith({
      memory: "128MB",
      timeoutSeconds: 120,
    })
    .pubsub
    .schedule("0 0 * * 0") // Weekly: Sunday at midnight UTC
    .timeZone("UTC")
    .onRun(async (context) => {
      console.log("[CleanupTokens] Scheduled token cleanup started...");

      const cutoff90 = new Date();
      cutoff90.setDate(cutoff90.getDate() - 90); // 90 days ago

      const cutoff180 = new Date();
      cutoff180.setDate(cutoff180.getDate() - 180); // 180 days ago

      let deletedCount = 0;
      let errorCount = 0;

      try {
        // ── Query 1: Inactive tokens ────────────────────────────────
        // We filter client-side for stale (older than 90 days) and
        // permanently invalid (have deactivationReason).
        // This avoids needing a composite index for a != query.
        const allInactive = await db
            .collection("device_tokens")
            .where("active", "==", false)
            .get();

        // Separate into stale (old) and invalid (permanent failure) tokens
        const staleTokens = allInactive.docs.filter(
          (doc) => doc.data().updatedAt && doc.data().updatedAt.toDate() <= cutoff90
        );
        const invalidTokens = allInactive.docs.filter(
          (doc) => doc.data().deactivationReason
        );

        // ── Query 2: Orphaned active tokens (migration safety net) ──
        // Catch active=true docs that were never deactivated (e.g. old
        // {userId}_{platform} docs that never received a push after the
        // migration to auto-generated IDs).
        //
        // These have stale tokens that will never be valid, but are still
        // marked active. We remove them after 180 days of no updates.
        const orphanedActive = await db
            .collection("device_tokens")
            .where("active", "==", true)
            .where("updatedAt", "<=", cutoff180)
            .get();

        // ── Merge & deduplicate by doc ID ───────────────────────────
        const seenIds = new Set();
        const tokensToRemove = [];
        for (const list of [staleTokens, invalidTokens, orphanedActive.docs]) {
          for (const doc of list) {
            if (!seenIds.has(doc.id)) {
              seenIds.add(doc.id);
              tokensToRemove.push(doc);
            }
          }
        }

        console.log(
          `[CleanupTokens] stale(>90d): ${staleTokens.length}, ` +
          `invalid: ${invalidTokens.length}, ` +
          `orphaned active(>180d): ${orphanedActive.size} ` +
          `→ removing ${tokensToRemove.length} total`
        );

        let batch = db.batch();
        let batchSize = 0;

        for (const doc of tokensToRemove) {
          batch.delete(doc.ref);
          batchSize++;
          deletedCount++;

          if (batchSize >= 500) {
            await batch.commit();
            batch = db.batch();
            batchSize = 0;
          }
        }

        if (batchSize > 0) {
          await batch.commit();
        }
      } catch (err) {
        errorCount++;
        console.error("[CleanupTokens] Error:", err);
      }

      console.log(
        `[CleanupTokens] Cleanup complete: ${deletedCount} deleted, ${errorCount} errors`
      );

      return null;
    });

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 8: onReviewChanged — Food Rating Aggregation  (Firestore trigger)
// ════════════════════════════════════════════════════════════════════════════

class PermanentValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = "PermanentValidationError";
  }
}

/**
 * When a review document is created, updated, or soft-deleted, recalculate
 * the food item's rating statistics incrementally and write them back.
 *
 * This runs server-side with admin privileges, eliminating the need for
 * client-side aggregation and the permissive `validFoodRatingStatsUpdate()`
 * Firestore rule.
 *
 * The aggregation is O(1): it reads the current food-item stats, adjusts
 * by ±1 for the changed rating, and writes back.  No full scan of reviews.
 *
 * @param {string} foodId — the food item whose stats to update
 * @param {Object} changes
 * @param {number|null} changes.removeRating — rating being removed (null if no remove)
 * @param {number|null} changes.addRating — rating being added (null if no add)
 */
async function updateFoodRatingStats(foodId, { removeRating, addRating }, eventId) {
  try {
    const foodRef = db.collection("food_items").doc(foodId);

    await db.runTransaction(async (transaction) => {
      const foodDoc = await transaction.get(foodRef);

      if (!foodDoc.exists) {
        console.warn("[onReviewChanged] Food item not found — skipping stats update");
        return;
      }

      const data = foodDoc.data() || {};
      const processedEventIds = data.processedEventIds || [];

      if (eventId && processedEventIds.includes(eventId)) {
        console.log("[onReviewChanged] Event already processed — skipping to prevent double application");
        return;
      }

      // ratingDistribution is authoritative.  The stored averageRating and
      // reviewCount are derived values (and may be rounded), so they are
      // recomputed from the bucket counts on every write.  This prevents
      // rounded stored averages from accumulating error across updates.
      const storedDistribution = data.ratingDistribution || {};
      const distribution = { "1": 0, "2": 0, "3": 0, "4": 0, "5": 0 };
      for (let i = 1; i <= 5; i++) {
        // Firestore map keys are always strings — must use String(i), not the
        // numeric i, otherwise storedDistribution[1] is always undefined and
        // every existing bucket is silently wiped, causing reviewCount → 0.
        const bucket = Number(storedDistribution[String(i)]);
        if (Number.isFinite(bucket) && bucket > 0) {
          distribution[String(i)] = bucket;
        }
      }

      // ── Validate ratings (reject outside 1–5 instead of clamping) ──
      const validateRating = (value, label) => {
        if (!Number.isInteger(value) || value < 1 || value > 5) {
          throw new PermanentValidationError(
            `[onReviewChanged] Invalid ${label} rating ${value} for food ${foodId} — expected integer 1-5`,
          );
        }
        return value;
      };

      // ── Derive stats from the distribution buckets ──────────────────
      const statsFromDistribution = (dist) => {
        let count = 0;
        let sum = 0;
        for (let i = 1; i <= 5; i++) {
          // Keys are strings — use String(i) for consistent access.
          const bucket = Number(dist[String(i)]) || 0;
          count += bucket;
          sum += i * bucket;
        }
        return { count, average: count > 0 ? sum / count : 0 };
      };

      // ── Apply the rating change to the distribution buckets ─────────
      if (removeRating != null) {
        const r = validateRating(removeRating, "remove");
        // Use String(r) — the distribution object has string keys.
        distribution[String(r)] = Math.max(0, (distribution[String(r)] || 0) - 1);
      }

      if (addRating != null) {
        const r = validateRating(addRating, "add");
        distribution[String(r)] = (distribution[String(r)] || 0) + 1;
      }

      // ── Recompute reviewCount and averageRating from the updated
      //    distribution — never from previously rounded averages ───────
      const updatedStats = statsFromDistribution(distribution);
      const reviewCount = updatedStats.count;
      let averageRating = updatedStats.average;

      // ── Round to 1 decimal place for storage ────────────────────────
      averageRating = Math.round(averageRating * 10) / 10;

      // Track processed event IDs, capping at 20 to prevent unbounded array size growth
      const newProcessedEventIds = [...processedEventIds];
      if (eventId) {
        newProcessedEventIds.push(eventId);
        if (newProcessedEventIds.length > 20) {
          newProcessedEventIds.shift();
        }
      }

      transaction.update(foodRef, {
        averageRating: averageRating,
        reviewCount: reviewCount,
        ratingDistribution: distribution,
        processedEventIds: newProcessedEventIds,
      });

      console.log(
        `[onReviewChanged] Updated stats: ` +
        `avg=${averageRating}, count=${reviewCount}, ` +
        `remove=${removeRating ?? "-"}, add=${addRating ?? "-"}`
      );
    });
  } catch (err) {
    if (err instanceof PermanentValidationError) {
      console.error("[onReviewChanged] Permanent validation error — skipping permanently:", err.message);
      return; // Do not rethrow for permanent errors
    }
    console.error("[onReviewChanged] Error updating stats:", err);
    // Rethrow so transient transaction failures (e.g. contention) reject
    // the onReviewChanged handler and Cloud Functions retries the event.
    throw err;
  }
}

/**
 * Extract the shared review context for an onReviewChanged event.
 *
 * Returns null when there is nothing to process (no event data or no
 * foodId), so callers can skip. All before/after derived values are
 * normalized here to keep the trigger branches small.
 */
function extractReviewRatingContext(event) {
  if (!event.data) {
    console.log(
      `[onReviewChanged] Review has no event data — skipping`
    );
    return null;
  }

  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();
  const before = beforeData || null;
  const after = afterData || null;

  const beforeFoodId = before ? (before.foodId || null) : null;
  const afterFoodId = after ? (after.foodId || null) : null;
  const foodId = afterFoodId || beforeFoodId;

  if (!foodId) {
    console.log(
      `[onReviewChanged] Review has no foodId — skipping`
    );
    return null;
  }

  return {
    foodId,
    before,
    after,
    beforeRating: before ? (before.rating || null) : null,
    afterRating: after ? (after.rating || null) : null,
  };
}

/**
 * Apply a rating delta to the food item stats after logging.
 */
async function applyReviewRatingChange(foodId, { removeRating, addRating }, eventId, logMessage) {
  console.log(logMessage);
  await updateFoodRatingStats(foodId, {
    removeRating,
    addRating,
  }, eventId);
}

/** Case 1: Review document created. */
async function handleReviewCreated(ctx, event) {
  if (ctx.after.deleted) {
    console.log(
      `[onReviewChanged] Review created as deleted — skipping`
    );
    return;
  }
  await applyReviewRatingChange(ctx.foodId, {
    removeRating: null,
    addRating: ctx.afterRating,
  }, event.id, `[onReviewChanged] Review CREATED, rating=${ctx.afterRating}`);
}

/** Case 2: Review document deleted (hard delete of an active review). */
async function handleReviewDeleted(ctx, event) {
  if (ctx.before.deleted || ctx.beforeRating == null) {
    console.log(
      `[onReviewChanged] Review hard-deleted, already soft-deleted or no rating — skipping`
    );
    return;
  }
  await applyReviewRatingChange(ctx.foodId, {
    removeRating: ctx.beforeRating,
    addRating: null,
  }, event.id, `[onReviewChanged] Review DELETED, rating=${ctx.beforeRating}`);
}

/** Case 3: Review document updated — soft-delete, restore, or rating edit. */
async function handleReviewUpdated(ctx, event) {
  if (ctx.before.deleted && ctx.after.deleted) {
    console.log(
      `[onReviewChanged] Review already deleted — skipping`
    );
    return;
  }

  if (!ctx.before.deleted && ctx.after.deleted) {
    await applyReviewRatingChange(ctx.foodId, {
      removeRating: ctx.beforeRating,
      addRating: null,
    }, event.id, `[onReviewChanged] Review SOFT-DELETED, rating=${ctx.beforeRating}`);
    return;
  }

  if (ctx.before.deleted && !ctx.after.deleted) {
    await applyReviewRatingChange(ctx.foodId, {
      removeRating: null,
      addRating: ctx.afterRating,
    }, event.id, `[onReviewChanged] Review RESTORED, rating=${ctx.afterRating}`);
    return;
  }

  if (ctx.beforeRating !== ctx.afterRating) {
    await applyReviewRatingChange(ctx.foodId, {
      removeRating: ctx.beforeRating,
      addRating: ctx.afterRating,
    }, event.id,
      `[onReviewChanged] Review UPDATED, ` +
      `rating ${ctx.beforeRating} → ${ctx.afterRating}`
    );
    return;
  }

  console.log(
    `[onReviewChanged] Review updated metadata — no rating change`
  );
}
/**
 * Firestore trigger on reviews/{reviewId} for all write operations.
 *
 * Handles:
 * - **Create**: Adds the new rating to the food item's stats.
 * - **Update**: Removes the old rating and adds the new rating.
 * - **Delete / Soft-delete**: Removes the rating (handles both hard
 *   deletes and `deleted: true` soft-deletes).
 *
 * Uses [onDocumentWritten] to receive both before and after snapshots,
 * which allows computing the exact rating change regardless of operation.
 */
exports.onReviewChanged = onDocumentWritten(
  {
    document: "reviews/{reviewId}",
    region: "us-central1",
    retry: true,
  },
  async (event) => {
    const ctx = extractReviewRatingContext(event);
    if (!ctx) return;

    if (!ctx.before && ctx.after) {
      return handleReviewCreated(ctx, event);
    }

    if (ctx.before && !ctx.after) {
      return handleReviewDeleted(ctx, event);
    }

    return handleReviewUpdated(ctx, event);
  },
);

/**
 * Read a migration's persisted progress.
 *
 * Returns null when the migration is already marked completed (so the
 * caller exits immediately), otherwise the state document contents.
 */
async function readMigrationProgress(stateRef, label) {
  const stateSnap = await stateRef.get();
  const state = stateSnap.exists ? stateSnap.data() : {};
  if (state.status === "completed") {
    console.log(`${label} Migration already completed — skipping`);
    return null;
  }
  return state;
}

/**
 * Backfill a page of order documents with retry, collecting failures.
 *
 * Transient Firestore write failures are retried with bounded backoff
 * (withRetry) so a single blip never permanently skips an order.  Order IDs
 * that fail permanently are returned for persisting in the migration state
 * so operators can requeue them after completion.  NOT_FOUND (order deleted
 * mid-run) is excluded — there is nothing to requeue for a deleted order.
 */
async function backfillMigrationPage(docs, backfillFn, label) {
  let backfilledCount = 0;
  const failedOrderIds = [];
  for (const doc of docs) {
    try {
      const didBackfill = await withRetry(
        () => backfillFn(doc.ref, doc.data()),
        {
          maxRetries: 3,
          baseDelayMs: 200,
          maxDelayMs: 2000,
          isPermanent: (err) => isNotFoundError(err),
        },
      );
      if (didBackfill) {
        backfilledCount++;
      }
    } catch (err) {
      if (!isNotFoundError(err)) {
        failedOrderIds.push(doc.id);
      }
      console.error(
        `${label} Backfill failed after retries: ${err.message}`
      );
    }
  }
  return { backfilledCount, failedOrderIds };
}

/**
 * Retry backfill on previously-failed order IDs (final phase).
 *
 * The forward-only cursor walks past failures on non-final pages, so those
 * orders would never be revisited by the main walk.  Deleted orders are
 * resolved (dropped) rather than failed again.  Returns the set of resolved
 * IDs plus the number successfully backfilled this pass.
 */
async function retryMigrationFailures(orderIds, backfillFn, label) {
  const resolvedRetryIds = new Set();
  let backfilledCount = 0;
  for (const orderId of orderIds) {
    try {
      const orderDoc = await db.collection("orders").doc(orderId).get();
      if (!orderDoc.exists) {
        resolvedRetryIds.add(orderId);
        continue;
      }
      const didBackfill = await withRetry(
        () => backfillFn(orderDoc.ref, orderDoc.data()),
        {
          maxRetries: 3,
          baseDelayMs: 200,
          maxDelayMs: 2000,
          isPermanent: (err) => isNotFoundError(err),
        },
      );
      if (didBackfill) backfilledCount++;
      resolvedRetryIds.add(orderId);
    } catch (err) {
      if (!isNotFoundError(err)) {
        console.error(
          `${label} Retry backfill failed for ${orderId}: ${err.message}`
        );
      }
    }
  }
  return { resolvedRetryIds, backfilledCount };
}

/**
 * Merge prior and current failure IDs, deduplicating and capping so the
 * state doc stays bounded: a failed order ID is tens of bytes, so retaining
 * every failure since the start could exceed Firestore's 1 MiB document
 * limit and stall the write.
 */
function accumulateMigrationFailedIds(priorFailedIds, failedOrderIds) {
  return [
    ...new Set([...priorFailedIds, ...failedOrderIds]),
  ].slice(-MAX_FAILED_IDS);
}
// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 9: migrateLegacyOrderFoodIds  (Scheduled — one-time backfill)
// ════════════════════════════════════════════════════════════════════════════
//
// Backfills the denormalised `foodIds` array on legacy orders that are ALREADY
// in COLLECTED status.  The review-eligibility rule (validReviewOrderEligibility)
// requires `order.data.foodIds.hasAny([foodId])` for a review to be created,
// but orders created before that field existed — and never updated since — are
// never touched by onOrderStatusChanged / onNewOrder, so they would remain
// permanently non-reviewable.  This migration closes that gap.
//
// Design:
//   • Bounded     — processes at most MIGRATION_BATCH_SIZE orders per run
//                   (well inside the 120s timeout); the Cloud Scheduler job
//                   invokes it every 5 minutes.
//   • Resumable   — progress is persisted in a state document
//                   (migrations/food_ids_backfill) holding the phase
//                   ('collected' → 'COLLECTED' → 'completed') and the cursor
//                   (last processed order document ID), so a rerun resumes
//                   exactly where the previous run stopped — even after a
//                   timeout or crash.
//   • Idempotent  — reuses backfillOrderFoodIds(), which no-ops when the
//                   order already has a populated `foodIds` list, so a rerun
//                   never rewrites migrated orders.
//   • Self-terminating — once both status spellings are exhausted the state
//                   is marked 'completed' and subsequent runs exit immediately.
//
// Both status spellings are covered because the app writes lowercase
// 'collected' (OrderStatus.toShortString) while legacy writes and the rules
// also accept uppercase 'COLLECTED'.  Each phase uses a separate `==` query
// ordered by document ID (automatic single-field index — no composite index
// required) with its own cursor.

/** Max orders processed per scheduled run. */
const MIGRATION_BATCH_SIZE = 100;

/**
 * Max permanently-failed order IDs retained in the migration state doc.
 * Keeps the state document far below Firestore's 1 MiB limit while still
 * exposing the most recent failures to operators for requeueing.
 */
const MAX_FAILED_IDS = 1000;

/** Firestore state document for the legacy foodIds backfill migration. */
const MIGRATION_STATE_REF = db.collection("migrations").doc("food_ids_backfill");

exports.migrateLegacyOrderFoodIds = functions
    .runWith({
      memory: "256MB",
      timeoutSeconds: 120,
    })
    .pubsub
    .schedule("every 5 minutes")
    .onRun(async (context) => {
      console.log("[migrateFoodIds] Scheduled run started...");

      const state = await readMigrationProgress(
        MIGRATION_STATE_REF,
        "[migrateFoodIds]",
      );
      if (!state) return null;

      // phase: 'collected' | 'COLLECTED' | 'completed'
      const phase = state.phase || "collected";
      const cursor = state.cursor || null;

      // ── Fetch one bounded page of COLLECTED orders ───────────────
      let query = db
          .collection("orders")
          .where("status", "==", phase)
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(MIGRATION_BATCH_SIZE);
      if (cursor) {
        query = query.startAfter(cursor);
      }

      const snapshot = await query.get();
      console.log(
        `[migrateFoodIds] Phase '${phase}', ` +
        `found ${snapshot.size} order(s)`
      );

      let { backfilledCount, failedOrderIds } = await backfillMigrationPage(
        snapshot.docs,
        backfillOrderFoodIds,
        "[migrateFoodIds]",
      );

      // ── Advance phase / cursor ────────────────────────────────────
      // Fewer results than the batch size means the phase is exhausted.
      const isLastPage = snapshot.size < MIGRATION_BATCH_SIZE;
      let nextPhase = phase;
      let nextCursor = isLastPage
        ? null
        : snapshot.docs[snapshot.docs.length - 1].id;

      // Phase advance: the first phase ('collected') always moves to
      // 'COLLECTED' once exhausted. Completion of the final phase is decided
      // after the retry pass below.
      if (isLastPage) {
        nextPhase = phase === "collected" ? "COLLECTED" : phase;
      }

      // Accumulated permanently-failed order IDs across ALL runs so far,
      // preserved across merged state writes (merge: true) — operators can
      // read them from the state document and requeue after completion.
      // To requeue, reset the state doc status back to 'collected' (and
      // cursor to null) so a scheduled run picks the list up again.
      const priorFailedIds = Array.isArray(state.failedOrderIds)
        ? state.failedOrderIds
        : [];
      const accumulatedFailedIds = accumulateMigrationFailedIds(
        priorFailedIds,
        failedOrderIds,
      );

      // ── Bounded retry pass for previously-failed orders (final phase) ──
      // Re-attempt up to MIGRATION_BATCH_SIZE accumulated failed IDs per run
      // once the final phase's walk is exhausted — the slice keeps a single
      // run within the function timeout; IDs beyond the slice stay in
      // failedOrderIds for the next run.
      const retryCandidates = accumulatedFailedIds.slice(0, MIGRATION_BATCH_SIZE);
      let resolvedRetryIds = new Set();
      if (isLastPage && phase === "COLLECTED" &&
          retryCandidates.length > 0) {
        const retry = await retryMigrationFailures(
          retryCandidates,
          backfillOrderFoodIds,
          "[migrateFoodIds]",
        );
        resolvedRetryIds = retry.resolvedRetryIds;
        backfilledCount += retry.backfilledCount;
      }

      // Successfully retried (or deleted) orders are resolved — drop them
      // from the retained list so failedOrderIds tracks only PENDING
      // failures and completion stays reachable even after many distinct
      // failures over the life of the migration. Unattempted IDs (beyond
      // this run's slice) and still-failing IDs remain for the next run.
      const remainingFailedIds = accumulatedFailedIds.filter(
        (id) => !resolvedRetryIds.has(id),
      );

      // Complete only when the final phase's last page AND the retry pass
      // produced no failures; otherwise stay in the final phase so the next
      // scheduled run retries (cursor resets to null — backfill no-ops on
      // tagged orders and the retry pass re-attempts the pending IDs).
      if (isLastPage && phase === "COLLECTED") {
        nextPhase = remainingFailedIds.length === 0 ? "completed" : phase;
      }

      const stateUpdate = {
        phase: nextPhase,
        cursor: nextCursor,
        processedCount: (state.processedCount || 0) + backfilledCount,
        failedOrderIds: remainingFailedIds,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (nextPhase === "completed") {
        stateUpdate.status = "completed";
        stateUpdate.completedAt = admin.firestore.FieldValue.serverTimestamp();
      }
      await MIGRATION_STATE_REF.set(stateUpdate, { merge: true });

      console.log(
        `[migrateFoodIds] Run complete: ${backfilledCount} backfilled this run, ` +
        `total=${stateUpdate.processedCount}, ` +
        `failedTotal=${remainingFailedIds.length}, ` +
        `nextPhase='${nextPhase}'`
      );

      // Return a summary of what this run did: null (above) means the
      // migration is already completed and nothing was processed, while this
      // object reports the run's outcome — the return value distinguishes
      // the two paths instead of always returning null.
      return {
        phase: nextPhase,
        backfilled: backfilledCount,
        failed: remainingFailedIds.length,
        processedTotal: stateUpdate.processedCount,
      };
    });

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 9b: migrateLegacyOrderCafes  (Scheduled — every 5 min)
// ════════════════════════════════════════════════════════════════════════════

// Per-cafe admin scoping (firestore.rules adminServesOrder()) relies on the
// server-authoritative `cafes` array on every order.  Orders created before
// that field existed (legacy orders) or by legacy app builds lack it, so a
// cafe-scoped admin query (`cafes array-contains cafeName`) would silently
// miss them.  This migration tags every legacy order, mirroring the
// migrateLegacyOrderFoodIds design:
//
//   • Bounded     — processes at most MIGRATION_BATCH_SIZE orders per run.
//   • Resumable   — progress persisted in migrations/order_cafes_backfill
//                   with a document-ID cursor; reruns resume where they left
//                   off, even after a timeout or crash.
//   • Idempotent  — reuses backfillOrderCafes(), which no-ops on valid
//                   non-empty `cafes` lists and repairs absent/empty/malformed
//                   values (derived cafes, or the UNASSIGNED sentinel for
//                   cafeless orders), so reruns never rewrite migrated orders.
//   • Self-terminating — once every order has been visited the state is
//                   marked 'completed' and subsequent runs exit immediately.
//
// Unlike the foodIds migration (which only needs COLLECTED orders for review
// eligibility), cafe scoping affects every order status — an admin must see
// pending/accepted/preparing/ready orders too — so this walks the whole
// `orders` collection ordered by document ID (automatic single-field index;
// no composite index required).

/** Firestore state document for the legacy order-cafes backfill migration. */
const MIGRATION_CAFES_STATE_REF = db
    .collection("migrations")
    .doc("order_cafes_backfill");

exports.migrateLegacyOrderCafes = functions
    .runWith({
      memory: "256MB",
      timeoutSeconds: 120,
    })
    .pubsub
    .schedule("every 5 minutes")
    .onRun(async () => {
      console.log("[migrateCafes] Scheduled run started...");

      const state = await readMigrationProgress(
        MIGRATION_CAFES_STATE_REF,
        "[migrateCafes]",
      );
      if (!state) return null;

      const cursor = state.cursor || null;

      // ── Fetch one bounded page of orders (any status) ────────────
      let query = db
          .collection("orders")
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(MIGRATION_BATCH_SIZE);
      if (cursor) {
        query = query.startAfter(cursor);
      }

      const snapshot = await query.get();
      console.log(
        `[migrateCafes] Found ${snapshot.size} order(s)`
      );

      let { backfilledCount, failedOrderIds } = await backfillMigrationPage(
        snapshot.docs,
        backfillOrderCafes,
        "[migrateCafes]",
      );

      const isLastPage = snapshot.size < MIGRATION_BATCH_SIZE;
      const nextCursor = isLastPage
        ? null
        : snapshot.docs[snapshot.docs.length - 1].id;

      const priorFailedIds = Array.isArray(state.failedOrderIds)
        ? state.failedOrderIds
        : [];
      // Deduplicate first, then cap so the state doc stays bounded: a failed
      // order ID is tens of bytes, so retaining every failure since the start
      // could exceed Firestore's 1 MiB document limit and stall the write.
      const accumulatedFailedIds = accumulateMigrationFailedIds(
        priorFailedIds,
        failedOrderIds,
      );

      // ── Bounded retry pass for previously-failed orders ──────────────
      // The forward-only cursor walks past failures on non-final pages, so
      // those orders would never be revisited by the main walk. When the
      // walk is exhausted, re-attempt up to MIGRATION_BATCH_SIZE accumulated
      // failed IDs per run — the slice keeps a single run well within the
      // function timeout; IDs beyond the slice stay in failedOrderIds and
      // are picked up by a later run.
      const retryCandidates = accumulatedFailedIds.slice(0, MIGRATION_BATCH_SIZE);
      let resolvedRetryIds = new Set();
      if (isLastPage && retryCandidates.length > 0) {
        const retry = await retryMigrationFailures(
          retryCandidates,
          backfillOrderCafes,
          "[migrateCafes]",
        );
        resolvedRetryIds = retry.resolvedRetryIds;
        backfilledCount += retry.backfilledCount;
      }

      // Successfully retried (or deleted) orders are resolved — drop them
      // from the retained list so failedOrderIds tracks only PENDING
      // failures and completion stays reachable even after many distinct
      // failures over the life of the migration. Unattempted IDs (beyond
      // this run's slice) and still-failing IDs remain for the next run.
      const remainingFailedIds = accumulatedFailedIds.filter(
        (id) => !resolvedRetryIds.has(id),
      );

      // Mark complete only on a failure-free final page AND retry pass;
      // otherwise keep the migration active so the next run retries the
      // remaining failed orders (cursor resets to null — backfill no-ops on
      // tagged orders and the retry pass re-attempts the pending IDs).
      const completedThisRun = isLastPage && remainingFailedIds.length === 0;

      const stateUpdate = {
        cursor: nextCursor,
        processedCount: (state.processedCount || 0) + backfilledCount,
        failedOrderIds: remainingFailedIds,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (completedThisRun) {
        stateUpdate.status = "completed";
        stateUpdate.completedAt = admin.firestore.FieldValue.serverTimestamp();
      }
      await MIGRATION_CAFES_STATE_REF.set(stateUpdate, { merge: true });

      console.log(
        `[migrateCafes] Run complete: ${backfilledCount} backfilled this run, ` +
        `total=${stateUpdate.processedCount}, ` +
        `failedTotal=${remainingFailedIds.length}, ` +
        `completed=${completedThisRun}`
      );

      // Return a summary of what this run did: null (above) means the
      // migration is already completed and nothing was processed, while this
      // object reports the run's outcome — the return value distinguishes
      // the two paths instead of always returning null.
      return {
        completed: completedThisRun,
        backfilled: backfilledCount,
        failed: remainingFailedIds.length,
        processedTotal: stateUpdate.processedCount,
      };
    });

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 10: auditReviewCreationRate  (Scheduled — every 24 hours)
// ════════════════════════════════════════════════════════════════════════════

// Review-flooding guard (Phase 15, Part 7). Firestore rules cannot enforce a
// global per-user rate limit across the whole `reviews` collection (no
// aggregation), so a daily scheduled audit moppers up. It detects users who
// created an abnormally high number of NEW reviews in the trailing 24 hours
// and persists a diagnostic record for admins to review.
//
// Design:
//   • Non-destructive — it ONLY audits. It never deletes reviews, never
//     mutates ratings, and never changes an account's status automatically
//     (strike/suspension remains a deliberate admin decision, Part 8).
//   • Bounded      — reads at most REVIEW_AUDIT_MAX_SCAN reviews per daily run,
//                     so cost grows with ONE day's activity, not the whole DB.
//   • Idempotent   — output keyed by ISO date; a rerun within the same day
//                     overwrites the same document instead of duplicating rows.
//   • Privacy      — records only the user UID (identifier allowed for
//     auditability); no email, review text, or PII is logged (Part 15).

/** Max reviews scanned per daily run. */
const REVIEW_AUDIT_MAX_SCAN = 50000;

/** Per-user NEW-review ceiling in a trailing 24h window before flagging. */
const REVIEW_DAILY_CAP = 10;

exports.auditReviewCreationRate = functions
    .runWith({
      memory: "256MB",
      timeoutSeconds: 240,
    })
    .pubsub
    .schedule("every 24 hours")
    .onRun(async (context) => {
      console.log("[auditReviews] Scheduled flood audit started...");

      const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);

      const counts = {};
      let scanned = 0;
      let lastTimestamp = null;

      const limit = Math.min(REVIEW_AUDIT_MAX_SCAN, 500);
      for (;;) {
        let q = db
            .collection("reviews")
            .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(cutoff))
            .orderBy("createdAt")
            .limit(limit);
        if (lastTimestamp) {
          q = q.startAfter(lastTimestamp);
        }
        const snapshot = await q.get();
        if (snapshot.empty) break;

        let latest = null;
        for (const doc of snapshot.docs) {
          scanned++;
          const data = doc.data();
          latest = data && data.createdAt;
          const uid = data && data.userId;
          if (typeof uid === "string" && uid.length > 0) {
            counts[uid] = (counts[uid] || 0) + 1;
          }
        }
        lastTimestamp = latest;
        if (snapshot.size < limit || scanned >= REVIEW_AUDIT_MAX_SCAN) break;
      }

      const suspects = Object.keys(counts)
          .filter((uid) => counts[uid] > REVIEW_DAILY_CAP)
          .map((uid) => ({ userId: uid, count: counts[uid] }))
          .sort((a, b) => b.count - a.count);

      // Persist the audit result keyed by the calendar date (idempotent).
      const dateKey = new Date().toISOString().slice(0, 10);
      await db.collection("review_audit").doc(dateKey).set({
        windowStart: admin.firestore.Timestamp.fromDate(cutoff),
        windowEnd: admin.firestore.FieldValue.serverTimestamp(),
        scannedReviews: scanned,
        flaggedUsers: suspects,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(
        `[auditReviews] Scanned ${scanned} review(s); ` +
        `flagged ${suspects.length} user(s) exceeding cap ` +
        `(${REVIEW_DAILY_CAP}/day): ` +
        (suspects.map((s) => `${s.userId}(${s.count})`).join(", ") || "(none)")
      );

      return null;
    });
