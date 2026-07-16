/**
 * CampusBite Cloud Functions
 * ===========================
 *
 * Combined deployment of all CampusBite Cloud Functions:
 *
 * 1) processExpiredPickups — Scheduled (every 5 min) automatic strike engine.
 *    Reads expired 'ready' orders, issues strikes, updates users, creates audit logs.
 *
 * 2) onOrderStatusChanged — Firestore trigger on orders/{orderId}.
 *    When status transitions to 'ready', writes readyAt, pickupDeadline, deadlineStatus.
 *
 * 3) deleteCloudinaryImage — Callable function.
 *    Deletes an image from Cloudinary (admin only, secrets-protected).
 *
 * 4) cleanupDeletedNotifications — Scheduled (every 24h) cleanup of old soft-deleted
 *    notifications.
 */

// ── Imports ────────────────────────────────────────────────────────────────

const functions = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

admin.initializeApp();

const db = admin.firestore();
const PICKUP_WINDOW_MINUTES = 20;

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

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 1: processExpiredPickups  (Scheduled — every 5 minutes)
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
      const processedStudentIds = new Set();

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
                processedStudentIds.add(orderSnapshot.data().studentId);
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
      // This runs outside the transaction — Firestore writes triggered by
      // the transaction above are already committed by this point.
      //
      // Phase 7: Create notifications for each student who received a strike.
      // Also create ACCOUNT_SUSPENDED notifications for students who were
      // newly suspended (strikeCount >= 2).
      // These are fire-and-forget; failures to create a notification do NOT
      // affect the strike processing outcome (business logic independence).
      if (processedCount > 0) {
        console.log(`[AutoStrike] Creating notifications for ${processedStudentIds.size} student(s)`);
        for (const studentId of processedStudentIds) {
          try {
            // Phase 7: ORDER_NO_SHOW notification
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

            // Phase 7: ACCOUNT_SUSPENDED notification
            // Read the (already-updated) user doc to check if suspended
            // Using orderId in eventId supports re-suspension after pardon
            const userDoc = await db.collection("users").doc(studentId).get();
            const strikeCount = userDoc.data()?.strikeCount ?? 0;
            if (strikeCount >= 2) {
              const orderId = orderSnapshot.id;
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
            // Notifications must never break business logic.
            console.error(
              `[AutoStrike] Failed to create notification for ${studentId}:`, notifErr
            );
          }
        }
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

    // Only proceed if status changed to "ready"
    if (!beforeData || !afterData) return;
    if (beforeData.status === afterData.status) return;
    if (afterData.status !== "ready") return;

    // Idempotency: if readyAt already exists, do nothing
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

    // Phase 7: Notify the student that their order is ready
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

/**
 * When a student places a new order, notify all admin users.
 *
 * Queries for all users with role === 'admin' and creates a NEW_ORDER
 * notification for each admin. Uses per-admin eventId for dedup.
 *
 * Phase 7: Only Firestore delivery — FCM will be added later.
 */
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
      // Find all admin users to notify
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
                   `Tsh ${Math.round(totalAmount)}.`, // using Tsh as the currency
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
      // Notifications must never break business logic — this is a trigger,
      // so the order creation itself is unaffected by notification failures.
      console.error(`[onNewOrder] Error:`, err);
    }
  },
);

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 4: deleteCloudinaryImage  (Callable — admin only)
// ════════════════════════════════════════════════════════════════════════════

// Define secrets that will be set via Firebase CLI
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
// FUNCTION 4: cleanupDeletedNotifications  (Scheduled — every 24 hours)
// ════════════════════════════════════════════════════════════════════════════

/**
 * Clean up soft-deleted notifications older than 180 days.
 *
 * Runs once every 24 hours.
 * Never deletes active (non-deleted) notifications.
 */
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
      cutoff.setDate(cutoff.getDate() - 180); // 180 days ago

      let deletedCount = 0;
      let errorCount = 0;

      try {
        // Query soft-deleted notifications older than 180 days
        const oldNotifications = await db
            .collection("notifications")
            .where("deleted", "==", true)
            .where("deletedAt", "<=", cutoff)
            .get();

        console.log(
          `[CleanupNotifications] Found ${oldNotifications.size} old deleted notification(s)`
        );

        // Delete in batches of 500 (Firestore batch limit)
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

        // Commit any remaining batch
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
