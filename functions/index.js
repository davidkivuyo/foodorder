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
 * 11) auditReviewCreationRate — Scheduled (every 24h) review-rate guardrail.
 */

// ── Imports ────────────────────────────────────────────────────────────────

const crypto = require("crypto");
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
    err.code === "already-exists" ||
    /already exists/i.test(String(err.message || ""))
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
        err.code === "NOT_FOUND" || // doc already deleted
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
    // Step 1: Query active tokens for the recipient
    const tokensSnapshot = await db
        .collection("device_tokens")
        .where("userId", "==", recipientId)
        .where("active", "==", true)
        .get();

    if (tokensSnapshot.empty) {
      console.log(
        `[sendPush] No active tokens for ${recipientRole} — skipping push`
      );
      return { sent: 0, total: 0, failures: [] };
    }

    let activeTokens = tokensSnapshot.docs.map((doc) => ({
      token: doc.data().token,
      docId: doc.id,
    }));

    totalAttempted = activeTokens.length;

    console.log(
      `[sendPush] Sending push to ${activeTokens.length} device(s) for ${recipientRole}`
    );

    // Step 2: Build the base FCM message (tokens are added per attempt)
    function buildMessage(tokenList) {
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

    // Step 3: Send the multicast with retry for transient failures
    //
    // Idempotent delivery uses a lease-based claim-then-finalize pattern:
    //   1. BEFORE each attempt, transactionally claim each remaining token
    //      via recordDelivery().  If the record doesn't exist, a new
    //      'pending' claim is created.  If it exists but the lease has
    //      expired (120s), the claim is reclaimed.  Terminal records
    //      ('delivered'/'failed') are skipped.
    //   2. Send only to tokens whose claims were CREATED or RECLAIMED
    //      this round.  Tokens with active leases (from a prior attempt
    //      that hasn't expired) are skipped — they are still in flight.
    //   3. AFTER the multicast, finalize each claimed record as
    //      'delivered' or 'failed' based on the FCM response.
    //      Terminal records never have a lease (claimedAt is cleared).
    //
    // This lease mechanism provides crash recovery: if the function
    // crashes after claiming but before finalizing, the lease expires
    // and a subsequent retry reclaims the token and delivers again.
    // At most one push per device is delivered per active lease period.
    //
    let remainingTokens = activeTokens;
    let retryAttempt = 0;
    const maxFcmRetries = 3;

    while (remainingTokens.length > 0 && retryAttempt <= maxFcmRetries) {
      // ── Step 3a: Claim tokens for this attempt ──────────────────
      // Atomically create a 'pending' record for each token.  Only tokens
      // whose claim succeeds (first-time claim) get sent.  Tokens with
      // existing claims (ALREADY_EXISTS) are already handled.
      const claimedTokens = [];
      const claimPromises = [];
      // claimErrors is hoisted to the while-loop level so errors from one
      // iteration are not discarded when remainingTokens is reassigned below.
      let claimErrors = [];

      if (eventId) {
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

        const skippedCount = claimPromises.length -
          claimedTokens.length - claimErrors.length;
        if (skippedCount > 0) {
          console.log(
            `[sendPush] Skipped ${skippedCount} already-claimed device(s)`
          );
        }
      } else {
        // No eventId — no idempotency possible; send to all remaining.
        claimedTokens.push(...remainingTokens);
      }

      // Early exit: nothing to send and nothing to retry.
      if (claimedTokens.length === 0 && claimErrors.length === 0) {
        break;
      }

      if (claimedTokens.length === 0) {
        // No claims, but claimErrors exist with retries left.
        // Skip the send+process block and go directly to iteration setup.
      } else {
        // ── Some claims succeeded — send the multicast ─────────────
        const message = buildMessage(claimedTokens);

        let response;
        try {
          response = await withRetry(
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
          break;
        }

        // ── Step 3b: Process FCM responses ────────────────────────
        const tokensToRetry = [];
        const tokensToDeactivate = [];
        const tokensToRelease = [];
        let newlySent = 0;
        const finalizePromises = [];

        for (let i = 0; i < response.responses.length; i++) {
          const resp = response.responses[i];
          const tokenEntry = claimedTokens[i];

          if (resp.success) {
            newlySent++;
            if (eventId) {
              finalizePromises.push(
                finalizeDelivery(eventId, tokenEntry.docId, "delivered", null, tokenEntry.claimId)
              );
            }
            continue;
          }

          if (isFcmPermanentError(resp)) {
            if (eventId) {
              finalizePromises.push(
                finalizeDelivery(
                  eventId,
                  tokenEntry.docId,
                  "failed",
                  (resp.error && (resp.error.code || resp.error.message)) || "permanent_failure",
                  tokenEntry.claimId,
                )
              );
            }
            tokensToDeactivate.push({
              docId: tokenEntry.docId,
              reason: (resp.error && (resp.error.code || resp.error.message)) || "permanent_failure",
            });
            failures.push({
              tokenDocId: tokenEntry.docId,
              error: (resp.error && (resp.error.code || resp.error.message)) || "permanent_failure",
              transient: false,
            });
          } else {
            const errorMsg = (resp.error && (resp.error.code || resp.error.message)) || "transient_failure";
            if (retryAttempt < maxFcmRetries) {
              tokensToRelease.push({ tokenEntry, errorMsg });
            } else {
              if (eventId) {
                finalizePromises.push(
                  finalizeDelivery(eventId, tokenEntry.docId, "failed", errorMsg, tokenEntry.claimId)
                );
              }
              failures.push({
                tokenDocId: tokenEntry.docId,
                error: errorMsg,
                transient: true,
              });
            }
          }
        }

        sentCount += newlySent;

        // ── Release pending claims for transient failures ──────────
        if (tokensToRelease.length > 0 && eventId) {
          const releaseResults = await Promise.allSettled(
            tokensToRelease.map(async ({ tokenEntry, errorMsg }) => {
              const released = await releaseDeliveryClaim(eventId, tokenEntry.docId, tokenEntry.claimId);
              return { tokenEntry, errorMsg, released };
            }),
          );

          for (const result of releaseResults) {
            if (result.status === "rejected") {
              console.warn(
                `[sendPush] releaseDeliveryClaim rejected: ${result.reason?.message || "unknown error"}`
              );
              continue;
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
        } else if (tokensToRelease.length > 0) {
          for (const { tokenEntry, errorMsg } of tokensToRelease) {
            tokensToRetry.push(tokenEntry);
            console.warn(
              `[sendPush] Transient failure, ` +
              `will retry (attempt ${retryAttempt + 1}/${maxFcmRetries}): ${errorMsg}`
            );
          }
        }

        if (finalizePromises.length > 0) {
          await Promise.allSettled(finalizePromises);
        }

        if (tokensToDeactivate.length > 0) {
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

        // Merge FCM retry tokens into the next iteration.
        remainingTokens = tokensToRetry;
      }

      // ── Merge claim errors into the next iteration ──────────────
      // claimErrors are tokens whose recordDelivery call threw (unexpected
      // Firestore error).  They were not sent this round and must be retried.
      // Merge them into remainingTokens so the next while-loop iteration
      // attempts them again.
      if (claimErrors.length > 0) {
        remainingTokens.push(...claimErrors);
      }

      if (remainingTokens.length > 0 && retryAttempt < maxFcmRetries) {
        const delay = Math.min(200 * Math.pow(2, retryAttempt), 4000);
        const jitter = Math.random() * delay;
        console.log(
          `[sendPush] Retrying ${remainingTokens.length} token(s) ` +
          `in ${Math.round(delay + jitter)}ms (attempt ${retryAttempt + 2}/${maxFcmRetries + 1})`
        );
        await new Promise((resolve) => setTimeout(resolve, delay + jitter));
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
    if (
      err.message &&
      (err.message.includes("no valid tokens") ||
       err.message.includes("no tokens"))
    ) {
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
    return await withRetry(
      async () => {
        const doc = await ref.get();
        if (!doc.exists) {
          // Document already deleted — the claim is already released.
          return true;
        }

        // ── Ownership check: verify claimId matches ───────────────
        if (claimId && doc.data().claimId !== claimId) {
          // The claim was reclaimed by a newer worker.  Return true
          // because from the old worker's perspective the claim was
          // already released (the new worker now owns it).  This avoids
          // a redundant finalizeDelivery attempt from the caller.
          console.warn(
            `[releaseDeliveryClaim] claimId mismatch: ` +
            `expected ${claimId}, got ${doc.data().claimId} — ` +
            `claim already reclaimed, treating as released`
          );
          return true;
        }

        await ref.delete();
        return true;
      },
      {
        maxRetries: 2,
        baseDelayMs: 100,
        maxDelayMs: 1000,
        isPermanent: (err) =>
          err.code === "PERMISSION_DENIED",
      },
    );
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
    expiredAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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
    `(pickup deadline expired)`
  );

  return true;
}

exports.processExpiredPickups = functions
    .runWith({
      memory: "256MB",
      timeoutSeconds: 120,
    })
    .pubsub
    .schedule("every 5 minutes")
    .onRun(async (context) => {
      console.log("[PickupExpiry] Scheduled run started...");

      const now = admin.firestore.Timestamp.now();
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
            .where("pickupDeadline", "<=", now)
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
// `items` data — the authoritative purchase record.  Orders that already
// have a populated `foodIds` list are left unchanged.

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
 * No-op when the order already has a populated `foodIds` list, so already
 * migrated orders are never rewritten.  Never clears or overwrites an
 * existing list.
 *
 * @param {admin.firestore.DocumentReference} orderRef
 * @param {Object} orderData
 * @return {Promise<boolean>} true when a backfill write was performed
 */
async function backfillOrderFoodIds(orderRef, orderData) {
  if (!orderData) return false;
  // Only a NON-EMPTY foodIds list counts as already populated.  An empty
  // array (or missing / non-array values) falls through to derivation from
  // the authoritative `items` data so the order becomes reviewable.
  if (Array.isArray(orderData.foodIds) && orderData.foodIds.length > 0) {
    return false; // Already populated.
  }
  const foodIds = deriveOrderFoodIds(orderData.items);
  if (!foodIds) return false; // Nothing derivable — leave unchanged.
  await orderRef.update({
    foodIds,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(
    "[backfillFoodIds] Backfilled foodIds for order"
  );
  return true;
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
 * Items that resolve to a missing food document keep their client-supplied
 * price (there is nothing authoritative to compare against); the order's
 * overall `price` is recomputed as the sum of all resolved line totals.
 *
 * @param {admin.firestore.DocumentReference} orderRef
 * @param {Object} orderData
 * @return {Promise<number|null>} the recomputed authoritative total, or
 *   null when no correction was made (pricing already authoritative).
 */
async function normalizeOrderPricing(orderRef, orderData) {
  if (!orderData || !Array.isArray(orderData.items) || orderData.items.length === 0) {
    return null;
  }

  const resolvedTotal = { value: 0 };
  const prices = [];

  for (const item of orderData.items) {
    const foodId = item && (item.foodItemId || item.id);
    let unitPrice = typeof item.price === "number" ? item.price : 0;

    if (typeof foodId === "string" && foodId.length > 0) {
      try {
        const snap = await orderRef.firestore
            .collection("food_items")
            .doc(foodId)
            .get();
        if (snap.exists) {
          const menuData = snap.data();
          if (menuData && typeof menuData.price === "number") {
            unitPrice = menuData.price;
          }
        }
      } catch (err) {
        console.warn(
          `[normalizeOrderPricing] food_items/${foodId} lookup failed: ${err.message}`
        );
        // Fall through with the client-supplied price — not authoritative
        // but non-destructive.
      }
    }

    const quantity = typeof item.quantity === "number" ? item.quantity : 1;
    prices.push({ price: unitPrice, quantity });
    resolvedTotal.value += unitPrice * quantity;
  }

  const storedTotal =
    typeof orderData.price === "number" ? orderData.price : 0;
  const needsPriceFix = Math.abs(resolvedTotal.value - storedTotal) > 0.001;
  const needsItemFix = prices.some(
    (p, i) => p.price !== (orderData.items[i] && orderData.items[i].price)
  );

  if (!needsPriceFix && !needsItemFix) {
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
// FUNCTION 2: onOrderStatusChanged  (Firestore trigger)
// ════════════════════════════════════════════════════════════════════════════

exports.onOrderStatusChanged = onDocumentUpdated(
  {
    document: "orders/{orderId}",
    region: "us-central1",
    // Retry the whole event when the backfill rethrows a transient error,
    // so a failed backfill is not acknowledged as a successful event.
    retry: true,
  },
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();

    if (!beforeData || !afterData) return;

    // Backfill `foodIds` on legacy orders (see helpers above) before any
    // review eligibility can be evaluated.  Runs on every order update —
    // including the admin's transition to COLLECTED — so legacy orders
    // become reviewable as soon as they are touched.
    //
    // A failed backfill must NOT be acknowledged as a successful event:
    // transient write failures are retried in-invocation (withRetry), and
    // if the backfill still fails the error is rethrown after logging so
    // Cloud Functions retries the whole event.  Retries are safe because
    // backfillOrderFoodIds is idempotent (no-op when foodIds is already
    // populated) and the ORDER_READY notification is deduplicated by
    // eventId in createNotification — no side effects are duplicated.
    try {
      await withRetry(
        () => backfillOrderFoodIds(event.data.after.ref, afterData),
        {
          maxRetries: 3,
          baseDelayMs: 200,
          maxDelayMs: 2000,
          isPermanent: (err) => err.code === "NOT_FOUND", // order deleted mid-run
        },
      );
    } catch (err) {
      console.error(
        `[onOrderStatusChanged] foodIds backfill failed: ${err.message}`
      );
      // NOT_FOUND means the order no longer exists — nothing left to
      // backfill and no status/notification work is meaningful for a
      // deleted order, so return early instead of retrying a permanent
      // failure.  Any other failure is rethrown so the event is not
      // acknowledged as successful.
      if (err.code === "NOT_FOUND") {
        return;
      }
      throw err;
    }

    if (beforeData.status === afterData.status) return;
    if (afterData.status !== "ready") return;

    if (afterData.readyAt != null) return;

    const now = admin.firestore.Timestamp.now();
    const deadline = new admin.firestore.Timestamp(
      now.seconds + PICKUP_WINDOW_MINUTES * 60,
      now.nanoseconds,
    );

    await event.data.after.ref.update({
      readyAt: now,
      pickupDeadline: deadline,
      pickupWindowMinutes: PICKUP_WINDOW_MINUTES,
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
          message: `Your order #${event.params.orderId} is ready! ` +
                   `Please collect it within ${PICKUP_WINDOW_MINUTES} minutes.`,
          orderId: event.params.orderId,
          deepLink: `/orders/${event.params.orderId}`,
          eventId: notificationEventId("ORDER_READY", event.params.orderId),
          createdBy: "system",
        });
      } catch (notifErr) {
        console.error(
          `[onOrderStatusChanged] Failed to create ORDER_READY notification:`, notifErr
        );
      }
    }
  },
);

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 3: onNewOrder  (Firestore trigger — document created)
// ════════════════════════════════════════════════════════════════════════════

exports.onNewOrder = onDocumentCreated(
  {
    document: "orders/{orderId}",
    region: "us-central1",
    // Retry the whole event when the backfill rethrows a transient error,
    // so a failed backfill is not acknowledged as a successful event.
    retry: true,
  },
  async (event) => {
    const orderData = event.data.data();
    if (!orderData) {
      console.log("[onNewOrder] No data for order — skipping");
      return;
    }

    // Backfill `foodIds` when an order was created without it (e.g. by a
    // legacy app build whose create payload predates the field).  Orders
    // from the current app already include the field, so this is a no-op.
    //
    // A failed backfill must NOT be acknowledged as a successful event:
    // transient write failures are retried in-invocation (withRetry), and
    // if the backfill still fails the error is rethrown after logging so
    // Cloud Functions retries the whole event.  Retries are safe because
    // backfillOrderFoodIds is idempotent and NEW_ORDER notifications are
    // deduplicated by eventId in createNotification — no side effects are
    // duplicated.
    try {
      await withRetry(
        () => backfillOrderFoodIds(event.data.ref, orderData),
        {
          maxRetries: 3,
          baseDelayMs: 200,
          maxDelayMs: 2000,
          isPermanent: (err) => err.code === "NOT_FOUND", // order deleted mid-run
        },
      );
    } catch (err) {
      console.error(
        `[onNewOrder] foodIds backfill failed: ${err.message}`
      );
      // NOT_FOUND means the order no longer exists — nothing left to
      // backfill and no admin notification is meaningful for a deleted
      // order, so return early instead of retrying a permanent failure.
      // Any other failure is rethrown so the event is not acknowledged
      // as successful.
      if (err.code === "NOT_FOUND") {
        return;
      }
      throw err;
    }

    const studentId = orderData.studentId || orderData.userId;
    const studentName = orderData.userName || "A student";
    const orderId = event.params.orderId;

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

    console.log("[onNewOrder] New order received");

    try {
      const adminSnapshot = await db
          .collection("users")
          .where("role", "==", "admin")
          .get();

      if (adminSnapshot.empty) {
        console.log("[onNewOrder] No admin users found — skipping notifications");
        return;
      }

      console.log(`[onNewOrder] Notifying ${adminSnapshot.size} admin(s)`);

      const adminIds = adminSnapshot.docs.map((doc) => doc.id);
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
    if (!event.data) {
      console.log(
        `[onReviewChanged] Review has no event data — skipping`
      );
      return;
    }

    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();

    // ── Determine the operation and extract rating changes ───────────
    const before = beforeData || null;
    const after = afterData || null;

    const beforeFoodId = before ? (before.foodId || null) : null;
    const afterFoodId = after ? (after.foodId || null) : null;
    const foodId = afterFoodId || beforeFoodId;

    if (!foodId) {
      console.log(
        `[onReviewChanged] Review has no foodId — skipping`
      );
      return;
    }

    const beforeRating = before ? (before.rating || null) : null;
    const afterRating = after ? (after.rating || null) : null;
    const beforeDeleted = before ? (before.deleted || false) : false;
    const afterDeleted = after ? (after.deleted || false) : false;

    // ── Case 1: Document created (no before) ─────────────────────────
    if (!before && after) {
      if (after.deleted) {
        console.log(
          `[onReviewChanged] Review created as deleted — skipping`
        );
        return;
      }
      console.log(
        `[onReviewChanged] Review CREATED, rating=${afterRating}`
      );
      await updateFoodRatingStats(foodId, {
        removeRating: null,
        addRating: afterRating,
      }, event.id);
      return;
    }

    // ── Case 2: Document deleted (no after) ──────────────────────────
    if (before && !after) {
      if (before.deleted || beforeRating == null) {
        console.log(
          `[onReviewChanged] Review hard-deleted, already soft-deleted or no rating — skipping`
        );
        return;
      }
      console.log(
        `[onReviewChanged] Review DELETED, rating=${beforeRating}`
      );
      await updateFoodRatingStats(foodId, {
        removeRating: beforeRating,
        addRating: null,
      }, event.id);
      return;
    }

    // ── Case 3: Document updated (both before and after) ─────────────
    if (before && after) {
      // Both already deleted — no rating change to process.  The rating
      // was already removed when the review was soft-deleted (Case 3a).
      // Any subsequent update to a deleted document (e.g. updatedAt)
      // must not modify stats again.
      if (before.deleted && after.deleted) {
        console.log(
          `[onReviewChanged] Review already deleted — skipping`
        );
        return;
      }

      // ── Sub-case 3a: Soft-delete toggle ────────────────────────────
      if (!before.deleted && after.deleted) {
        console.log(
          `[onReviewChanged] Review SOFT-DELETED, rating=${beforeRating}`
        );
        await updateFoodRatingStats(foodId, {
          removeRating: beforeRating,
          addRating: null,
        }, event.id);
        return;
      }

      // ── Sub-case 3b: Restore from soft-delete ──────────────────────
      if (before.deleted && !after.deleted) {
        console.log(
          `[onReviewChanged] Review RESTORED, rating=${afterRating}`
        );
        await updateFoodRatingStats(foodId, {
          removeRating: null,
          addRating: afterRating,
        }, event.id);
        return;
      }

      // ── Sub-case 3c: Rating change (edit) ─────────────────────────
      if (beforeRating !== afterRating) {
        console.log(
          `[onReviewChanged] Review UPDATED, ` +
          `rating ${beforeRating} → ${afterRating}`
        );
        await updateFoodRatingStats(foodId, {
          removeRating: beforeRating,
          addRating: afterRating,
        }, event.id);
        return;
      }

      // ── Sub-case 3d: Non-rating update (comment, tags, etc.) ───────
      console.log(
        `[onReviewChanged] Review updated metadata — no rating change`
      );
    }
  },
);

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

      // ── Read persisted progress ───────────────────────────────────
      const stateSnap = await MIGRATION_STATE_REF.get();
      const state = stateSnap.exists ? stateSnap.data() : {};

      if (state.status === "completed") {
        console.log(
          "[migrateFoodIds] Migration already completed — skipping"
        );
        return null;
      }

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

      // ── Backfill each order (idempotent; failures never stall the run) ──
      // Transient Firestore write failures are retried with bounded backoff
      // (withRetry) so a single blip never permanently skips an order — the
      // cursor only advances after the page has been processed.  Order IDs
      // that fail permanently are persisted in the migration state so
      // operators can requeue them after completion.
      let backfilledCount = 0;
      const failedOrderIds = [];
      for (const doc of snapshot.docs) {
        try {
          const didBackfill = await withRetry(
            () => backfillOrderFoodIds(doc.ref, doc.data()),
            {
              maxRetries: 3,
              baseDelayMs: 200,
              maxDelayMs: 2000,
              isPermanent: (err) => err.code === "NOT_FOUND", // order deleted mid-run
            },
          );
          if (didBackfill) {
            backfilledCount++;
          }
        } catch (err) {
          // Final failure after retries — persist the order ID for later
          // requeue and log loudly.  NOT_FOUND (order deleted mid-run) is
          // excluded: there is nothing to requeue for a deleted order.
          // The cursor still advances so the migration keeps moving.
          if (err.code !== "NOT_FOUND") {
            failedOrderIds.push(doc.id);
          }
          console.error(
            `[migrateFoodIds] Backfill failed ` +
            `after retries: ${err.message}`
          );
        }
      }

      // ── Advance phase / cursor ────────────────────────────────────
      // Fewer results than the batch size means the phase is exhausted.
      const isLastPage = snapshot.size < MIGRATION_BATCH_SIZE;
      let nextPhase = phase;
      let nextCursor = isLastPage
        ? null
        : snapshot.docs[snapshot.docs.length - 1].id;

      if (isLastPage) {
        nextPhase = phase === "collected" ? "COLLECTED" : "completed";
      }

      // Accumulated permanently-failed order IDs across ALL runs so far,
      // preserved across merged state writes (merge: true) — operators can
      // read them from the state document and requeue after completion.
      // To requeue, reset the state doc status back to 'collected' (and
      // cursor to null) so a scheduled run picks the list up again.
      const priorFailedIds = Array.isArray(state.failedOrderIds)
        ? state.failedOrderIds
        : [];
      const accumulatedFailedIds = [
        ...new Set([...priorFailedIds, ...failedOrderIds]),
      ];

      const stateUpdate = {
        phase: nextPhase,
        cursor: nextCursor,
        processedCount: (state.processedCount || 0) + backfilledCount,
        failedOrderIds: accumulatedFailedIds,
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
        `failedTotal=${accumulatedFailedIds.length}, ` +
        `nextPhase='${nextPhase}'`
      );

      return null;
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
