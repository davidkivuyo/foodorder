/**
 * CampusBite Cloud Functions
 * ===========================
 *
 * Combined deployment of all CampusBite Cloud Functions:
 *
 * 1) processExpiredPickups — Scheduled (every 5 min) automatic strike engine.
 * 2) onOrderStatusChanged — Firestore trigger on orders/{orderId}.
 * 3) onNewOrder — Firestore trigger on orders/{orderId} (document created).
 * 4) onNewNotification — Firestore trigger on notifications/{notificationId} (FCM push).
 * 5) deleteCloudinaryImage — Callable function (admin only, secrets-protected).
 * 6) cleanupDeletedNotifications — Scheduled (every 24h) cleanup.
 * 7) cleanupInactiveTokens — Scheduled (weekly) cleanup of stale device tokens.
 * 8) onReviewChanged — Firestore trigger on reviews/{reviewId} — recalculates
 *    food item rating statistics when a review is created, updated, or deleted.
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
 * Derive the account status string from a strike count.
 * @param {number} strikeCount
 * @return {string} 'ACTIVE' or 'SUSPENDED'
 */
function deriveAccountStatus(strikeCount) {
  return strikeCount >= 2 ? "SUSPENDED" : "ACTIVE";
}

/**
 * Build a unique eventId for a notification to enable duplicate prevention.
 * @param {string} action — e.g. 'STRIKE_ISSUED', 'ORDER_NO_SHOW'
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
  // Duplicate prevention
  if (eventId) {
    const existing = await db
        .collection("notifications")
        .where("eventId", "==", eventId)
        .limit(1)
        .get();

    if (!existing.empty) {
      console.log(`[createNotification] Skipping duplicate: ${eventId}`);
      return null;
    }
  }

  try {
    const docRef = await db.collection("notifications").add({
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
    });

    console.log(`[createNotification] Created ${type} for ${recipientId}: ${docRef.id}`);
    return docRef.id;
  } catch (err) {
    console.error(`[createNotification] Error creating ${type}:`, err);
    return null;
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
          `[recordDelivery] Lease expired for ${docId} ` +
          `(${Math.round(elapsedMs / 1000)}s old, old claimId=${data.claimId}) — reclaiming`
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
      `[recordDelivery] Transaction error for ${docId}: ${err.message} — propagating`
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
        `[sendPush] No active tokens for ${recipientRole} ${recipientId} — skipping push`
      );
      return { sent: 0, total: 0, failures: [] };
    }

    let activeTokens = tokensSnapshot.docs.map((doc) => ({
      token: doc.data().token,
      docId: doc.id,
    }));

    totalAttempted = activeTokens.length;

    console.log(
      `[sendPush] Sending push to ${activeTokens.length} device(s) for ${recipientRole} ${recipientId}`
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
                `[sendPush] Claim failed for token ${t.docId}: ` +
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
                `[sendPush] Transient failure for token ${tokenEntry.docId}, ` +
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
                `[sendPush] Could not release claim for token ${tokenEntry.docId} — ` +
                `pending claim preserved for lease-based recovery: ${errorMsg}`
              );
            }
          }
        } else if (tokensToRelease.length > 0) {
          for (const { tokenEntry, errorMsg } of tokensToRelease) {
            tokensToRetry.push(tokenEntry);
            console.warn(
              `[sendPush] Transient failure for token ${tokenEntry.docId}, ` +
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
                console.error(`[sendPush] Failed to deactivate token ${docId} after retries: ${err.message}`);
                return false;
              })
            ),
          );
          for (let i = 0; i < deactivateResults.length; i++) {
            if (deactivateResults[i].status === "rejected" || deactivateResults[i].value === false) {
              console.warn(`[sendPush] Could not deactivate token ${tokensToDeactivate[i].docId} — will be cleaned up by weekly scheduler`);
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
    console.error(`[sendPush] Error sending push to ${recipientId}:`, err);

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
          `[finalizeDelivery] claimId mismatch for ${docId}: ` +
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
      `[finalizeDelivery] Error updating ${docId} to ${status}: ${err.message}`
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
            `[releaseDeliveryClaim] claimId mismatch for ${docId}: ` +
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
      `[releaseDeliveryClaim] Failed to release claim ${docId}: ${err.message}`
    );
    return false;
  }
}
// ════════════════════════════════════════════════════════════════════════════

/**
 * Process a single expired order inside a Firestore transaction.
 *
 * @param {admin.firestore.Transaction} transaction
 * @param {admin.firestore.DocumentSnapshot} orderSnapshot
 * @return {Promise<boolean>} true if the strike was processed, false if skipped
 */
async function processExpiredOrder(transaction, orderSnapshot) {
  const orderRef = orderSnapshot.ref;
  const orderData = orderSnapshot.data();

  if (!orderData) return false;

  // ── Step 1: Verify order is still eligible ──────────────────────
  if (orderData.status !== "ready") return false;
  if (orderData.deadlineStatus !== "ACTIVE") return false;
  if (orderData.strikeProcessed === true) return false;

  const studentId = orderData.studentId;
  if (!studentId) {
    console.warn(`[AutoStrike] Order ${orderSnapshot.id} has no studentId – skipping`);
    return false;
  }

  // ── Step 2: Read the student document ───────────────────────────
  const userRef = db.collection("users").doc(studentId);
  const userSnapshot = await transaction.get(userRef);

  if (!userSnapshot.exists) {
    console.warn(`[AutoStrike] User ${studentId} not found – skipping order ${orderSnapshot.id}`);
    return false;
  }

  const userData = userSnapshot.data();
  if (!userData) return false;

  // ── Step 3: Calculate new strike values ─────────────────────────
  const currentStrikeCount = (userData.strikeCount ?? 0);
  const newStrikeCount = Math.min(currentStrikeCount + 1, 2);

  const orderUpdate = {
    status: "no_show",
    deadlineStatus: "EXPIRED",
    strikeProcessed: true,
    expiredAt: admin.firestore.FieldValue.serverTimestamp(),
    strikeIssuedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  const userUpdate = {
    strikeCount: newStrikeCount,
    accountStatus: deriveAccountStatus(newStrikeCount),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // ── Step 4: Update order ────────────────────────────────────────
  transaction.update(orderRef, orderUpdate);

  // ── Step 5: Update user ─────────────────────────────────────────
  transaction.update(userRef, userUpdate);

  // ── Step 6: Create audit log ────────────────────────────────────
  const auditRef = db.collection("audit_logs").doc();
  transaction.set(auditRef, {
    action: "automatic_no_show",
    orderId: orderSnapshot.id,
    studentId: studentId,
    previousStrikeCount: currentStrikeCount,
    newStrikeCount: newStrikeCount,
    performedBy: "system",
    reason: "pickup_deadline_expired",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(
    `[AutoStrike] Order ${orderSnapshot.id}: ` +
    `student=${studentId}, strikeCount ${currentStrikeCount} → ${newStrikeCount}, ` +
    `accountStatus=${deriveAccountStatus(newStrikeCount)}`
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
      console.log("[AutoStrike] Scheduled run started...");

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

        console.log(`[AutoStrike] Found ${expiredOrdersSnapshot.size} expired order(s)`);

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
              `[AutoStrike] Failed to process order ${orderSnapshot.id}:`, err
            );
          }
        });

        await Promise.all(promises);
      } catch (err) {
        console.error("[AutoStrike] Query or processing error:", err);
        throw err;
      }

      console.log(
        `[AutoStrike] Run complete: ${processedCount} processed, ${errorCount} errors`
      );

      // ── Notifications: Notify students about no-show strikes ──
      if (processedCount > 0) {
        console.log(`[AutoStrike] Creating notifications for ${processedRecords.length} student(s)`);
        for (const { studentId, orderId } of processedRecords) {
          try {
            // Create ORDER_NO_SHOW notification (existing Phase 7 behavior)
            await createNotification({
              recipientId: studentId,
              recipientRole: "student",
              type: "ORDER_NO_SHOW",
              title: "Order Missed — Strike Issued",
              message: "You did not collect your order on time. " +
                       "A strike has been added to your account. " +
                       "Repeated missed pickups may lead to account suspension.",
              deepLink: "/account",
              eventId: notificationEventId("AUTO_NO_SHOW", studentId),
              createdBy: "system",
            });

            // Create STRIKE_ISSUED notification (per-strike, per-order)
            await createNotification({
              recipientId: studentId,
              recipientRole: "student",
              type: "STRIKE_ISSUED",
              title: "Strike Added to Your Account",
              message: "You received a strike for not collecting your order #" +
                       `${orderId} on time. ` +
                       "Please collect future orders promptly.",
              deepLink: "/account",
              eventId: notificationEventId("STRIKE_ISSUED", orderId),
              createdBy: "system",
            });

            const userDoc = await db.collection("users").doc(studentId).get();
            const strikeCount = userDoc.data()?.strikeCount ?? 0;
            if (strikeCount >= 2) {
              await createNotification({
                recipientId: studentId,
                recipientRole: "student",
                type: "ACCOUNT_SUSPENDED",
                title: "Account Suspended",
                message: "Your account has been suspended due to " +
                         "repeated missed pickups. " +
                         "Please contact support to reactivate your account.",
                deepLink: "/account",
                eventId: `ACCOUNT_SUSPENDED_${studentId}_${orderId}`,
                createdBy: "system",
              });
            }
          } catch (notifErr) {
            console.error(
              `[AutoStrike] Failed to create notification for ${studentId}:`, notifErr
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
            `[AutoStrike] Sending PICKUP_REMINDER for ${ordersToRemind.length} order(s)`
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
                  `[AutoStrike] Failed to send PICKUP_REMINDER for order ${orderDoc.id}:`, notifErr
                );
              }
            },
          );

          await Promise.allSettled(reminderPromises);
        }
      } catch (reminderErr) {
        console.error("[AutoStrike] PICKUP_REMINDER error:", reminderErr);
      }

      return null;
    });

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 2: onOrderStatusChanged  (Firestore trigger)
// ════════════════════════════════════════════════════════════════════════════

exports.onOrderStatusChanged = onDocumentUpdated(
  {
    document: "orders/{orderId}",
    region: "us-central1",
  },
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();

    if (!beforeData || !afterData) return;
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
      `[onOrderStatusChanged] Order ${event.params.orderId} marked READY. ` +
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
  },
  async (event) => {
    const orderData = event.data.data();
    if (!orderData) {
      console.log(`[onNewOrder] No data for order ${event.params.orderId} — skipping`);
      return;
    }

    const studentId = orderData.studentId || orderData.userId;
    const studentName = orderData.userName || "A student";
    const orderId = event.params.orderId;
    const totalAmount = orderData.price || orderData.totalAmount || 0;

    console.log(`[onNewOrder] New order ${orderId} placed by ${studentName} (${studentId})`);

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
      console.log(`[onNewNotification] No data for notification ${event.params.notificationId} — skipping`);
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
        `for ${recipientRole} ${recipientId}`
      );
      return;
    }

    if (!allowedRoles.includes(recipientRole)) {
      console.log(
        `[onNewNotification] Role mismatch: ${notifData.type} not allowed for ` +
        `${recipientRole} ${recipientId} — skipping push`
      );
      return;
    }

    console.log(
      `[onNewNotification] Sending push for ${notifData.type} to ${recipientRole} ${recipientId}`
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
        `[onNewNotification] Push delivery for ${notificationId}: ` +
        `${result.sent}/${result.total} sent, ` +
        `${result.failures.length} failure(s)`
      );
    } catch (err) {
      // Push failure must never affect the Firestore notification.
      console.error(
        `[onNewNotification] Push delivery error for ${notificationId}:`, err
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

    const uid = request.auth.uid;
    const userDoc = await admin.firestore().collection("users").doc(uid).get();
    const userData = userDoc.data();

    if (!userData || userData.role !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only admins can delete images."
      );
    }

    const { publicId } = request.data;
    if (!publicId || typeof publicId !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "publicId is required and must be a string."
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
        console.warn(`[onReviewChanged] Food item ${foodId} not found — skipping stats update`);
        return;
      }

      const data = foodDoc.data() || {};
      const processedEventIds = data.processedEventIds || [];

      if (eventId && processedEventIds.includes(eventId)) {
        console.log(`[onReviewChanged] Event ${eventId} was already processed for food ${foodId} — skipping to prevent double application`);
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
        `[onReviewChanged] Updated stats for food ${foodId}: ` +
        `avg=${averageRating}, count=${reviewCount}, ` +
        `remove=${removeRating ?? "-"}, add=${addRating ?? "-"}, eventId=${eventId ?? "-"}`
      );
    });
  } catch (err) {
    if (err instanceof PermanentValidationError) {
      console.error(`[onReviewChanged] Permanent validation error for food ${foodId} — skipping permanently:`, err.message);
      return; // Do not rethrow for permanent errors
    }
    console.error(`[onReviewChanged] Error updating stats for food ${foodId}:`, err);
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
        `[onReviewChanged] Review ${event.params.reviewId} has no event data — skipping`
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
        `[onReviewChanged] Review ${event.params.reviewId} has no foodId — skipping`
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
          `[onReviewChanged] Review ${event.params.reviewId} created as deleted — skipping`
        );
        return;
      }
      console.log(
        `[onReviewChanged] Review ${event.params.reviewId} CREATED for food ${foodId}, rating=${afterRating}`
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
          `[onReviewChanged] Review ${event.params.reviewId} hard-deleted, already soft-deleted or no rating — skipping`
        );
        return;
      }
      console.log(
        `[onReviewChanged] Review ${event.params.reviewId} DELETED for food ${foodId}, rating=${beforeRating}`
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
          `[onReviewChanged] Review ${event.params.reviewId} already deleted — skipping`
        );
        return;
      }

      // ── Sub-case 3a: Soft-delete toggle ────────────────────────────
      if (!before.deleted && after.deleted) {
        console.log(
          `[onReviewChanged] Review ${event.params.reviewId} SOFT-DELETED for food ${foodId}, rating=${beforeRating}`
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
          `[onReviewChanged] Review ${event.params.reviewId} RESTORED for food ${foodId}, rating=${afterRating}`
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
          `[onReviewChanged] Review ${event.params.reviewId} UPDATED for food ${foodId}, ` +
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
        `[onReviewChanged] Review ${event.params.reviewId} updated metadata — no rating change`
      );
    }
  },
);
