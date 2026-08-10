// Copyright 2026 davidkivuyo, johnsonmushi, edwinkessy276-art, jugraki-art.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Phase A — NO-SHOW FOUNDATION: executable emulator/integration coverage.
//
// This suite runs the REAL Firestore emulator with the REAL firestore.rules
// loaded, and exercises the REAL exported Cloud Functions (direct handler
// invocation against the emulator-backed Admin SDK) for the no-show
// lifecycle. It complements the static guardrail tests in
// test/no_show_foundation_test.dart with behaviour-level assertions.
//
// Run (requires Java 21+ — e.g. JAVA_HOME=/usr/lib/jvm/java-25-openjdk):
//   npm run test:no-show:integration   (inside functions/)
// or, from the project root:
//   JAVA_HOME=/usr/lib/jvm/java-25-openjdk firebase emulators:exec \
//     --only firestore --project demo-foodorder \
//     "node --test functions/test/no_show_integration.test.js"

"use strict";

process.env.GCLOUD_PROJECT = "demo-foodorder";
process.env.FIRESTORE_EMULATOR_HOST = "localhost:8080";
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: "demo-foodorder" });

const fs = require("fs");
const path = require("path");
const { describe, it, before, beforeEach, after } = require("node:test");
const assert = require("node:assert");

// Requiring index.js initialises the default firebase-admin app against the
// emulator (via FIRESTORE_EMULATOR_HOST / FIREBASE_CONFIG). The handlers we
// invoke below share this same emulator-backed store.
const admin = require("firebase-admin");
const functionsModule = require("../index.js");
const db = admin.firestore();

const { initializeTestEnvironment } = require("@firebase/rules-unit-testing");
const { serverTimestamp } = require("firebase/firestore");

const RULES_FILE = path.join(__dirname, "../../firestore.rules");
const PICKUP_WINDOW_MINUTES = 20;

let testEnv;

// ── Fixtures ────────────────────────────────────────────────────────────────

function validOrderPayload(overrides = {}) {
  return {
    studentId: "student1",
    userName: "Test Student",
    items: [
      {
        foodItemId: "food_1",
        title: "Rice & Beans",
        price: 3000,
        quantity: 1,
        image: "",
        selectedCafe: "Cafe A",
      },
    ],
    price: 3000,
    status: "pending",
    createdAt: new Date(),
    updatedAt: new Date(),
    deadlineStatus: "NOT_READY",
    distanceMeters: 200,
    distanceCalculated: false,
    pickupWindowMinutes: 20,
    cafeId: "cafe1",
    cafeLocation: "Main Campus",
    ...overrides,
  };
}

/**
 * Construct the event shape consumed by the onDocumentUpdated handler.
 *
 * In production the Firestore trigger fires AFTER the write has already
 * landed, so the document on disk holds the after-state when the handler
 * runs. By default [afterData] is persisted to the referenced order
 * document before the event is returned, and the before/after snapshots
 * mirror the persisted before-state and after-state respectively.
 *
 * Replay tests (which intentionally seed or pre-transition the document
 * to the exact state a handler should observe) pass { persist: false } so
 * their deliberately staged document is left untouched.
 *
 * @param {string} orderId
 * @param {Object} beforeData — pre-transition document data
 * @param {Object} afterData — post-transition document data (persisted when persist=true)
 * @param {Object} [options]
 * @param {boolean} [options.persist=true]
 * @return {Promise<Object>} event payload for the handler
 */
async function makeStatusChangeEvent(orderId, beforeData, afterData, { persist = true } = {}) {
  const ref = db.collection("orders").doc(orderId);
  if (persist) {
    await ref.set(afterData);
  }
  const snapshot = (data) => ({ ref, data: () => data, exists: true });
  return {
    data: { before: snapshot(beforeData), after: snapshot(afterData) },
    params: { orderId },
  };
}

async function seedUsers() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const seed = ctx.firestore();
    await seed.collection("users").doc("student1").set({
      fullName: "Test Student",
      email: "student1@test.com",
      role: "student",
      accountStatus: "ACTIVE",
      strikeCount: 0,
      strikePercentage: 0,
      createdAt: new Date(),
    });
    await seed.collection("users").doc("admin1").set({
      fullName: "Admin One",
      email: "admin1@test.com",
      role: "admin",
      accountStatus: "ACTIVE",
      strikeCount: 0,
      strikePercentage: 0,
      createdAt: new Date(),
    });
  });
}

async function seedOrder(orderId, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("orders").doc(orderId).set(data);
  });
}

function studentDb() {
  return testEnv.authenticatedContext("student1", { email_verified: true }).firestore();
}

function adminDb() {
  return testEnv.authenticatedContext("admin1").firestore();
}

async function orderById(orderId) {
  const snap = await db.collection("orders").doc(orderId).get();
  return snap.exists ? snap.data() : null;
}

async function countNotifications(eventId) {
  const snap = await db
    .collection("notifications")
    .where("eventId", "==", eventId)
    .get();
  return snap.size;
}

function toMillis(value) {
  if (value instanceof admin.firestore.Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return value.seconds * 1000 + value.nanoseconds / 1e6;
}

function minutesBetween(a, b) {
  return Math.round((toMillis(a) - toMillis(b)) / 60000);
}

// ── Suite ───────────────────────────────────────────────────────────────────

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-foodorder",
    firestore: {
      rules: fs.readFileSync(RULES_FILE, "utf8"),
      host: "localhost",
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seedUsers();
});

after(async () => {
  await testEnv.cleanup();
});

describe("Firestore rules — authorization behaviour", () => {
  it("lets a verified student create a valid pending order", async () => {
    // The create rule requires createdAt to be the server-resolved write
    // timestamp (FieldValue.serverTimestamp() == request.time).
    await studentDb().collection("orders").doc("rule-ok-1").set(
      validOrderPayload({ createdAt: serverTimestamp() }),
    );
    const snap = await db.collection("orders").doc("rule-ok-1").get();
    assert.equal(snap.data().status, "pending");
  });

  it("denies student order updates — status and timestamps cannot be forged", async () => {
    await seedOrder("rule-upd-1", validOrderPayload({ status: "ready" }));
    const sdb = studentDb();
    await assert.rejects(
      sdb.collection("orders").doc("rule-upd-1").update({ status: "collected" }),
      /PERMISSION_DENIED/,
    );
    await assert.rejects(
      sdb.collection("orders").doc("rule-upd-1").update({
        status: "no_show",
        expiredAt: new Date(),
        noShowProcessed: true,
      }),
      /PERMISSION_DENIED/,
    );
    // Students have no order-update path at all (rules only allow admin
    // order updates), so the server-owned pickupDeadline cannot be forged
    // either — only the extendPickupDeadline callable may move it.
    await assert.rejects(
      sdb.collection("orders").doc("rule-upd-1").update({
        pickupDeadline: new Date(Date.now() + 60 * 60000),
      }),
      /PERMISSION_DENIED/,
    );
    const after = await orderById("rule-upd-1");
    assert.equal(after.status, "ready");
    assert.equal(after.noShowProcessed, undefined);
    assert.equal(after.pickupDeadline, undefined);
  });

  it("denies forged server-owned fields on order create", async () => {
    const sdb = studentDb();
    // The base payload is otherwise valid (server-resolved createdAt, no
    // deadline), so each denial is attributable to the forged field.
    const base = { createdAt: serverTimestamp() };
    for (const forged of [
      { readyAt: new Date() },
      { pickupDeadline: new Date() },
      { collectedAt: new Date() },
      { expiredAt: new Date() },
      { noShowProcessed: true },
    ]) {
      await assert.rejects(
        sdb.collection("orders").doc("rule-forge").set(
          validOrderPayload({ ...base, ...forged }),
        ),
        /PERMISSION_DENIED/,
        `forged field ${Object.keys(forged)[0]} must be rejected on create`,
      );
    }
  });

  it("lets an admin transition ready -> collected without touching protected fields", async () => {
    await seedOrder("rule-admin-1", validOrderPayload({ status: "ready" }));
    await adminDb().collection("orders").doc("rule-admin-1").update({
      status: "collected",
      updatedAt: new Date(),
    });
    const after = await orderById("rule-admin-1");
    assert.equal(after.status, "collected");
  });

  it("denies admin writes that modify server-owned timestamp fields", async () => {
    await seedOrder("rule-admin-2", validOrderPayload({ status: "ready" }));
    const adb = adminDb();
    // The no-show lifecycle fields recorded by the Cloud Functions are
    // server-owned: admin transitions (status only) may never stamp them.
    for (const forged of [
      { collectedAt: new Date() },
      { expiredAt: new Date() },
      { noShowProcessed: true },
    ]) {
      await assert.rejects(
        adb.collection("orders").doc("rule-admin-2").update({ status: "ready", ...forged }),
        /PERMISSION_DENIED/,
        `protected field ${Object.keys(forged)[0]} must be denied on admin update`,
      );
    }
  });

  it("lets an admin transition ready -> no_show directly", async () => {
    await seedOrder("rule-admin-3", validOrderPayload({ status: "ready" }));
    await adminDb().collection("orders").doc("rule-admin-3").update({
      status: "no_show",
      updatedAt: new Date(),
    });
    const after = await orderById("rule-admin-3");
    assert.equal(after.status, "no_show");
  });

  it("denies illegal backwards transitions (collected -> ready)", async () => {
    await seedOrder("rule-admin-4", validOrderPayload({ status: "collected" }));
    await assert.rejects(
      adminDb().collection("orders").doc("rule-admin-4").update({
        status: "ready",
        updatedAt: new Date(),
      }),
      /PERMISSION_DENIED/,
    );
  });
});

describe("Cloud Functions — no-show processing flow", () => {
  it("records authoritative readyAt + pickupDeadline on READY (Tests 1 & 2)", async () => {
    await seedOrder("flow-ready-1", validOrderPayload({ status: "pending" }));

    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "flow-ready-1",
      validOrderPayload({ status: "pending" }),
      validOrderPayload({ status: "ready" }),
    ));

    const after = await orderById("flow-ready-1");
    assert.ok(after.readyAt instanceof admin.firestore.Timestamp, "readyAt written");
    assert.ok(after.pickupDeadline instanceof admin.firestore.Timestamp, "pickupDeadline written");
    assert.equal(
      minutesBetween(after.pickupDeadline, after.readyAt),
      PICKUP_WINDOW_MINUTES,
      "pickup window is PICKUP_WINDOW_MINUTES from ready",
    );
    assert.equal(after.deadlineStatus, "ACTIVE");
    assert.equal(await countNotifications(`ORDER_READY_flow-ready-1`), 1);
  });

  it("records collectedAt on COLLECTED (Test 3)", async () => {
    await seedOrder("flow-col-1", validOrderPayload({ status: "ready" }));

    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "flow-col-1",
      validOrderPayload({ status: "ready" }),
      validOrderPayload({ status: "collected" }),
    ));

    const after = await orderById("flow-col-1");
    assert.ok(after.collectedAt instanceof admin.firestore.Timestamp, "collectedAt written");
    assert.equal(after.deadlineStatus, "COLLECTED");
  });

  it("is idempotent — an already-collected order is not re-written", async () => {
    await seedOrder("flow-col-2", validOrderPayload({
      status: "collected",
      collectedAt: new Date(Date.now() - 600000),
      deadlineStatus: "COLLECTED",
    }));

    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "flow-col-2",
      validOrderPayload({ status: "ready" }),
      validOrderPayload({ status: "collected", collectedAt: new Date(Date.now() - 600000) }),
      // Replay: the document is deliberately already-collected.
      { persist: false },
    ));

    const after = await orderById("flow-col-2");
    assert.equal(
      minutesBetween(after.collectedAt, new Date(Date.now() - 600000)),
      0,
      "existing collectedAt preserved",
    );
  });

  it("marks an expired READY order no_show (Tests 4 & 6)", async () => {
    await seedOrder("flow-exp-1", validOrderPayload({
      status: "ready",
      deadlineStatus: "ACTIVE",
      pickupDeadline: new Date(Date.now() - 5 * 60000),
    }));

    await functionsModule.processExpiredPickups.run({});

    const after = await orderById("flow-exp-1");
    assert.equal(after.status, "no_show");
    assert.equal(after.deadlineStatus, "EXPIRED");
    assert.equal(after.noShowProcessed, true);
    assert.ok(after.expiredAt instanceof admin.firestore.Timestamp, "expiredAt written");
    assert.equal(await countNotifications("ORDER_NO_SHOW_flow-exp-1"), 1);
  });

  it("leaves a not-yet-expired order untouched (premature expiry, Test 5)", async () => {
    await seedOrder("flow-future-1", validOrderPayload({
      status: "ready",
      deadlineStatus: "ACTIVE",
      pickupDeadline: new Date(Date.now() + 30 * 60000),
    }));

    await functionsModule.processExpiredPickups.run({});

    const after = await orderById("flow-future-1");
    assert.equal(after.status, "ready");
    assert.equal(after.deadlineStatus, "ACTIVE");
    assert.equal(after.noShowProcessed, undefined);
    assert.equal(after.expiredAt, undefined);
  });

  it("is idempotent across repeated runs (Test 7)", async () => {
    await seedOrder("flow-idem-1", validOrderPayload({
      status: "ready",
      deadlineStatus: "ACTIVE",
      pickupDeadline: new Date(Date.now() - 5 * 60000),
    }));

    await functionsModule.processExpiredPickups.run({});
    await functionsModule.processExpiredPickups.run({});

    const after = await orderById("flow-idem-1");
    assert.equal(after.status, "no_show");
    assert.equal(after.noShowProcessed, true);
    // Exactly one notification despite two runs.
    assert.equal(await countNotifications("ORDER_NO_SHOW_flow-idem-1"), 1);
  });

  it("skips orders already collected before processing (collection wins, Test 10)", async () => {
    await seedOrder("flow-collect-wins-1", validOrderPayload({
      status: "collected",
      deadlineStatus: "COLLECTED",
      collectedAt: new Date(Date.now() - 2 * 60000),
      noShowProcessed: false,
    }));
    // An expired-but-collected order must never be flipped back to no_show.
    await seedOrder("flow-collect-wins-2", validOrderPayload({
      status: "collected",
      deadlineStatus: "COLLECTED",
      collectedAt: new Date(Date.now() - 2 * 60000),
    }));

    await functionsModule.processExpiredPickups.run({});

    for (const orderId of ["flow-collect-wins-1", "flow-collect-wins-2"]) {
      const after = await orderById(orderId);
      assert.equal(after.status, "collected");
      assert.notEqual(after.noShowProcessed, true);
      assert.equal(after.expiredAt, undefined);
    }
  });

  it("keeps the final state consistent under a concurrent collect race", async () => {
    const seeded = validOrderPayload({
      status: "ready",
      deadlineStatus: "ACTIVE",
      pickupDeadline: new Date(Date.now() - 5 * 60000),
    });
    await seedOrder("flow-race-1", seeded);

    // Fire the processor and a rules-checked admin collect simultaneously.
    // The processor's transaction re-reads the order; the admin write is
    // evaluated against the rules. Whichever commits first wins and the
    // final state must never mix collected and no-show fields.
    const processing = functionsModule.processExpiredPickups.run({});
    const collecting = adminDb()
      .collection("orders")
      .doc("flow-race-1")
      .update({ status: "collected", updatedAt: new Date() })
      .catch((err) => {
        // If the processor won first, the rules reject no_show -> collected
        // (PERMISSION_DENIED) — that is the expected losing outcome. Any
        // other failure must surface so the test cannot mask an
        // infrastructure/emulator problem.
        if (err && (err.code === "permission-denied" || /PERMISSION_DENIED/.test(String(err.message || "")))) {
          return undefined;
        }
        throw err;
      });

    await Promise.all([processing, collecting]);

    const after = await orderById("flow-race-1");

    if (after.status === "collected") {
      // The collect won. In production the onOrderStatusChanged trigger
      // fires on the status change and records the authoritative
      // collectedAt + deadlineStatus COLLECTED; without the functions
      // emulator it does not fire automatically, so replay the collected
      // transition through the real handler before asserting the outcome.
      await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
        "flow-race-1",
        seeded,
        after,
        // Replay: the document already holds the post-race collected state.
        { persist: false },
      ));

      const final = await orderById("flow-race-1");
      const isCollected =
        final.status === "collected" &&
        final.noShowProcessed !== true &&
        final.expiredAt == null &&
        final.collectedAt instanceof admin.firestore.Timestamp &&
        final.deadlineStatus === "COLLECTED";
      assert.ok(
        isCollected,
        `collected outcome must include collectedAt + deadlineStatus ` +
        `COLLECTED and no no-show fields, got ${JSON.stringify(final)}`,
      );
      return;
    }

    // The collect lost (rules rejected no_show -> collected): the outcome
    // must be exactly the no-show state, never mixed with collected fields.
    const isNoShow =
      after.status === "no_show" && after.deadlineStatus === "EXPIRED" &&
      after.noShowProcessed === true && after.expiredAt != null &&
      after.collectedAt == null;
    assert.ok(
      isNoShow,
      `final state must be exactly no_show, got ${JSON.stringify(after)}`,
    );
  });

  it("keeps an admin-marked no_show order self-consistent", async () => {
    await seedOrder("flow-manual-ns-1", validOrderPayload({ status: "ready" }));

    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "flow-manual-ns-1",
      validOrderPayload({ status: "ready" }),
      validOrderPayload({ status: "no_show" }),
    ));

    const after = await orderById("flow-manual-ns-1");
    assert.equal(after.deadlineStatus, "EXPIRED");
    assert.equal(after.noShowProcessed, true);
    assert.ok(after.expiredAt instanceof admin.firestore.Timestamp, "expiredAt written");
  });
});
