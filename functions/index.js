/**
 * CampusBite Automatic Strike Engine
 * ====================================
 *
 * Scheduled Cloud Function that runs every 5 minutes.
 *
 * For every expired order (status == 'ready', deadlineStatus == 'ACTIVE',
 * pickupDeadline <= now) it executes ONE Firestore transaction that:
 *
 *   1. Reads the order – verifies status, deadlineStatus, and strikeProcessed
 *   2. Reads the user  – reads strikeCount from users/{studentId}
 *   3. Calculates       – newStrikeCount = min(current + 1, 2)
 *   4. Updates order    – status = 'no_show', deadlineStatus = 'EXPIRED',
 *                         strikeProcessed = true, expiredAt = now, strikeIssuedAt = now
 *   5. Updates user     – strikeCount, accountStatus, updatedAt
 *   6. Creates audit log – action = 'automatic_no_show', orderId, studentId, etc.
 *
 * The implementation is completely idempotent thanks to strikeProcessed.
 * Running it multiple times never duplicates strikes or audit logs.
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

/**
 * Derive the account status string from a strike count.
 * @param {number} strikeCount
 * @return {string} 'ACTIVE' or 'SUSPENDED'
 */
function deriveAccountStatus(strikeCount) {
  return strikeCount >= 2 ? "SUSPENDED" : "ACTIVE";
}

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

/**
 * Scheduled Cloud Function — runs every 5 minutes.
 *
 * Queries:
 *   orders WHERE status == 'ready'
 *          AND deadlineStatus == 'ACTIVE'
 *          AND pickupDeadline <= now
 *
 * This query requires a composite Firestore index on:
 *   orders collection: status ASC, deadlineStatus ASC, pickupDeadline ASC
 */
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

        // Process each expired order individually in its own transaction.
        // One failure must not stop processing of remaining orders.
        const promises = expiredOrdersSnapshot.docs.map(async (orderSnapshot) => {
          try {
            await db.runTransaction(async (transaction) => {
              // Re-read the document inside the transaction for consistency
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
