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
 */

// ── Imports ────────────────────────────────────────────────────────────────

const functions = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
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
              if (processed) processedCount++;
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
  },
);

// ════════════════════════════════════════════════════════════════════════════
// FUNCTION 3: deleteCloudinaryImage  (Callable — admin only)
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
