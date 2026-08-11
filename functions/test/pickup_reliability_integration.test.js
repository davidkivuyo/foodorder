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

// Phase B.2 — PICKUP RELIABILITY CALCULATION: executable emulator coverage.
//
// This suite runs the REAL Firestore emulator with the REAL firestore.rules
// loaded and exercises the REAL exported `onOrderStatusChanged` handler
// (which drives the reliability engine) against the emulator-backed Admin
// SDK, complementing the static guardrails in
// test/pickup_reliability_foundation_test.dart.
//
// It covers AGENTS.md Phase B.2 section 33, Tests 1-14:
//   1  New user           2  First collection      3  No-show
//   4  Normal ratio       5  Recent history        6  Old orders
//   7  Duplicate          8  Concurrent events     9  Cancelled order
//  10  READY order       11  Student write attack 12  Recent history limit
//  13  Score calculation 14  Zero division
//
// Run (requires Java 21+ — e.g. JAVA_HOME=/usr/lib/jvm/java-25-openjdk):
//   npm run test:reliability:integration   (inside functions/)
// or, from the project root:
//   JAVA_HOME=/usr/lib/jvm/java-25-openjdk firebase emulators:exec \
//     --only firestore --project demo-foodorder \
//     "node --test functions/test/pickup_reliability_integration.test.js"

"use strict";

process.env.GCLOUD_PROJECT = "demo-foodorder";
process.env.FIRESTORE_EMULATOR_HOST = "localhost:8080";
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: "demo-foodorder" });

const fs = require("fs");
const path = require("path");
const { describe, it, before, beforeEach, after } = require("node:test");
const assert = require("node:assert");

const admin = require("firebase-admin");
const functionsModule = require("../index.js");
const db = admin.firestore();

const { initializeTestEnvironment } = require("@firebase/rules-unit-testing");

const RULES_FILE = path.join(__dirname, "../../firestore.rules");

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

async function makeStatusChangeEvent(orderId, beforeData, afterData) {
  // Persist the after-state so the handler's transaction re-reads the real
  // document (the reliability engine reads the order fresh via
  // transaction.get). The event snapshots mirror the persisted states.
  const ref = db.collection("orders").doc(orderId);
  await ref.set(afterData);
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

async function userReliability() {
  const snap = await db.collection("users").doc("student1").get();
  return snap.exists ? snap.data().pickupReliability : undefined;
}

/**
 * Fire a terminal pickup transition through the real handler, driving the
 * reliability engine end-to-end. The order document is seeded to [status]
 * first so the engine's transaction observes the genuine terminal state.
 * @param {string} orderId
 * @param {'collected'|'no_show'} status
 */
async function fireTerminal(orderId, status) {
  await seedOrder(orderId, validOrderPayload({ status }));
  await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
    orderId,
    validOrderPayload({ status: "ready" }),
    validOrderPayload({ status }),
  ));
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

describe("Firestore rules — pickupReliability is server-authoritative", () => {
  it("denies a student who tries to write pickupReliability (Test 11)", async () => {
    await assert.rejects(
      studentDb().collection("users").doc("student1").update({
        pickupReliability: {
          eligibleOrders: 1000,
          collectedOrders: 1000,
          reliabilityScore: 100,
        },
      }),
      /PERMISSION_DENIED/,
    );
    const after = await db.collection("users").doc("student1").get();
    assert.equal(after.data().pickupReliability, undefined);
  });

  it("denies a student who tries to write pickupReliability via a favourite "
      + "list update (defence-in-depth)", async () => {
    await assert.rejects(
      studentDb().collection("users").doc("student1").update({
        favoriteMenu: ["food_1"],
        pickupReliability: { eligibleOrders: 999 },
      }),
      /PERMISSION_DENIED/,
    );
  });

  it("allows a valid favourite list update (string IDs, ≤ 5 elements)",
      async () => {
    await studentDb().collection("users").doc("student1").update({
      favoriteMenu: ["food_1", "food_2", "food_3"],
      favoriteMenuUpdatedAt: new Date(),
    });
    const snap = await db.collection("users").doc("student1").get();
    assert.deepEqual(
      snap.data().favoriteMenu, ["food_1", "food_2", "food_3"],
    );
  });

  it("denies a favourite list containing a non-string element", async () => {
    await assert.rejects(
      studentDb().collection("users").doc("student1").update({
        favoriteMenu: ["food_1", 123],
        favoriteMenuUpdatedAt: new Date(),
      }),
      /PERMISSION_DENIED/,
    );
  });

  it("denies a favourite list containing an empty string", async () => {
    await assert.rejects(
      studentDb().collection("users").doc("student1").update({
        favoriteMenu: ["food_1", ""],
        favoriteMenuUpdatedAt: new Date(),
      }),
      /PERMISSION_DENIED/,
    );
  });

  it("denies a favourite list with an oversized element (> 100 chars)",
      async () => {
    const tooLong = "x".repeat(101);
    await assert.rejects(
      studentDb().collection("users").doc("student1").update({
        favoriteMenu: ["food_1", tooLong],
        favoriteMenuUpdatedAt: new Date(),
      }),
      /PERMISSION_DENIED/,
    );
  });

  it("denies a favourite list with more than 5 elements", async () => {
    await assert.rejects(
      studentDb().collection("users").doc("student1").update({
        favoriteMenu: ["f1", "f2", "f3", "f4", "f5", "f6"],
        favoriteMenuUpdatedAt: new Date(),
      }),
      /PERMISSION_DENIED/,
    );
  });

  it("denies an admin who tries to forge reliabilityProcessed on an order", async () => {
    await seedOrder("rel-forge-1", validOrderPayload({ status: "ready" }));
    await assert.rejects(
      testEnv.authenticatedContext("admin1").firestore()
        .collection("orders").doc("rel-forge-1")
        .update({ status: "ready", reliabilityProcessed: true }),
      /PERMISSION_DENIED/,
    );
    // reliabilityOutcome is equally backend-immutable.
    await assert.rejects(
      testEnv.authenticatedContext("admin1").firestore()
        .collection("orders").doc("rel-forge-1")
        .update({ status: "ready", reliabilityOutcome: "NO_SHOW" }),
      /PERMISSION_DENIED/,
    );
  });

  it("lets a student read their own user document including the summary",
      async () => {
    // Backend writes a summary via the Admin SDK first.
    await seedOrder("rel-read-1", validOrderPayload({ status: "collected" }));
    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "rel-read-1",
      validOrderPayload({ status: "ready" }),
      validOrderPayload({ status: "collected" }),
    ));
    const snap = await studentDb().collection("users").doc("student1").get();
    assert.equal(snap.exists, true);
    assert.ok(snap.data().pickupReliability, "summary readable by owner");
  });
});

describe("Pickup reliability — lifetime metrics (Tests 1, 2, 3, 4, 14)", () => {
  it("Test 1 — a new user has no summary yet (neutral, never 0%)", async () => {
    assert.equal(await userReliability(), undefined);
  });

  it("Test 2 — first collection: 1 eligible, 1 collected → rate 100, "
      + "INSUFFICIENT_HISTORY", async () => {
    await fireTerminal("rel-t2-1", "collected");
    const s = await userReliability();
    assert.equal(s.eligibleOrders, 1);
    assert.equal(s.collectedOrders, 1);
    assert.equal(s.noShowOrders, 0);
    assert.equal(s.collectionRate, 100);
    assert.equal(s.status, "INSUFFICIENT_HISTORY");
  });

  it("Test 3 — no-show: 1 eligible, 0 collected → rate 0, "
      + "INSUFFICIENT_HISTORY, no restriction", async () => {
    await fireTerminal("rel-t3-1", "no_show");
    const s = await userReliability();
    assert.equal(s.eligibleOrders, 1);
    assert.equal(s.collectedOrders, 0);
    assert.equal(s.noShowOrders, 1);
    assert.equal(s.collectionRate, 0);
    assert.equal(s.status, "INSUFFICIENT_HISTORY");
  });

  it("Test 4 — normal ratio: 10 eligible, 8 collected, 2 no-show → 80",
      async () => {
    for (let i = 0; i < 10; i++) {
      const status = i < 8 ? "collected" : "no_show";
      await fireTerminal(`rel-t4-${i}`, status);
    }
    const s = await userReliability();
    assert.equal(s.eligibleOrders, 10);
    assert.equal(s.collectedOrders, 8);
    assert.equal(s.noShowOrders, 2);
    assert.equal(s.collectionRate, 80);
  });

  it("Test 14 — zero-collected division stays finite (rate 0, no NaN/Inf)",
      async () => {
    await fireTerminal("rel-t14-1", "no_show");
    const s = await userReliability();
    assert.ok(Number.isFinite(s.collectionRate), "collectionRate finite");
    assert.ok(Number.isFinite(s.reliabilityScore), "reliabilityScore finite");
    assert.equal(s.collectionRate, 0);
  });
});

describe("Pickup reliability — recent window (Tests 5, 6, 12)", () => {
  it("Tests 5 & 12 — only the latest 10 outcomes are retained and counted "
      + "in recentCollectionRate", async () => {
    // 12 events: 11 collected then 1 no-show. The recent window keeps the
    // latest 10 (the no-show plus 9 collected), so recent rate = 90%.
    for (let i = 0; i < 12; i++) {
      const status = i === 11 ? "no_show" : "collected";
      await fireTerminal(`rel-t5-${i}`, status);
    }
    const s = await userReliability();
    assert.equal(s.eligibleOrders, 12, "lifetime counts all 12");
    assert.equal(s.collectedOrders, 11);
    assert.equal(s.noShowOrders, 1);
    assert.equal(s.recentEligibleOrders, 10, "recent window capped at 10");
    assert.equal(s.recentCollectedOrders, 9);
    assert.equal(s.recentNoShowOrders, 1);
    assert.equal(s.recentCollectionRate, 90);
    assert.equal(s.recentPickupHistory.length, 10);
    // The oldest two collected orders are no longer in the recent window
    // but remain in the lifetime counters (Test 6).
    const orderIds = s.recentPickupHistory.map((e) => e.orderId);
    assert.ok(!orderIds.includes("rel-t5-0"));
    assert.ok(!orderIds.includes("rel-t5-1"));
    assert.ok(orderIds.includes("rel-t5-11"));
  });

  it("history timestamps equal the persisted terminal timestamps", async () => {
    // The trigger persists collectedAt/expiredAt BEFORE reliability
    // processing, so each recent-window history entry must carry the order's
    // authoritative terminal timestamp — never a fresh engine-side now.
    await fireTerminal("rel-ts-col", "collected");
    await fireTerminal("rel-ts-ns", "no_show");
    const colOrder = await db.collection("orders").doc("rel-ts-col").get();
    const nsOrder = await db.collection("orders").doc("rel-ts-ns").get();
    const s = await userReliability();
    const colEntry = s.recentPickupHistory.find((e) => e.orderId === "rel-ts-col");
    const nsEntry = s.recentPickupHistory.find((e) => e.orderId === "rel-ts-ns");
    assert.ok(colEntry && nsEntry, "history entries exist");
    assert.ok(
      colOrder.data().collectedAt instanceof admin.firestore.Timestamp,
      "collectedAt persisted",
    );
    assert.ok(
      nsOrder.data().expiredAt instanceof admin.firestore.Timestamp,
      "expiredAt persisted",
    );
    assert.equal(
      colEntry.timestamp.toMillis(),
      colOrder.data().collectedAt.toMillis(),
      "COLLECTED history timestamp matches persisted collectedAt",
    );
    assert.equal(
      nsEntry.timestamp.toMillis(),
      nsOrder.data().expiredAt.toMillis(),
      "NO_SHOW history timestamp matches persisted expiredAt",
    );
  });
});

describe("Pickup reliability — idempotency & concurrency (Tests 7, 8)", () => {
  it("Test 7 — processing the same order twice counts it exactly once",
      async () => {
    await seedOrder("rel-t7-1", validOrderPayload({ status: "collected" }));
    const event = await makeStatusChangeEvent(
      "rel-t7-1",
      validOrderPayload({ status: "ready" }),
      validOrderPayload({ status: "collected" }),
    );
    await functionsModule.onOrderStatusChanged.run(event);
    await functionsModule.onOrderStatusChanged.run(event);
    const s = await userReliability();
    assert.equal(s.eligibleOrders, 1);
    assert.equal(s.collectedOrders, 1);
    const order = await db.collection("orders").doc("rel-t7-1").get();
    assert.equal(order.data().reliabilityProcessed, true);
    // The counted outcome is persisted immutably alongside the marker.
    assert.equal(order.data().reliabilityOutcome, "COLLECTED");
  });

  it("regression — a pending-to-collected event (never READY) never counts",
      async () => {
    // An order that jumps straight from pending to collected never went
    // through READY, so it must not affect the reliability summary.
    await seedOrder("rel-invalid-col", validOrderPayload({ status: "pending" }));
    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "rel-invalid-col",
      validOrderPayload({ status: "pending" }),
      validOrderPayload({ status: "collected" }),
    ));
    assert.equal(await userReliability(), undefined, "no summary for pending→collected");
  });

  it("regression — a pending-to-no_show event (never READY) never counts",
      async () => {
    await seedOrder("rel-invalid-ns", validOrderPayload({ status: "pending" }));
    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "rel-invalid-ns",
      validOrderPayload({ status: "pending" }),
      validOrderPayload({ status: "no_show" }),
    ));
    assert.equal(await userReliability(), undefined, "no summary for pending→no_show");
  });

  it("Test 8 — concurrent COLLECTED and NO_SHOW events both land exactly once",
      async () => {
    // Fire a collected and a no-show event for the SAME student at the
    // same time. The transactions re-read the user document on conflict, so
    // both events must be reflected exactly once (eligible 2, collected 1,
    // no-show 1) regardless of commit order.
    await seedOrder("rel-t8-col", validOrderPayload({ status: "collected" }));
    await seedOrder("rel-t8-ns", validOrderPayload({ status: "no_show" }));
    await Promise.all([
      functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
        "rel-t8-col",
        validOrderPayload({ status: "ready" }),
        validOrderPayload({ status: "collected" }),
      )),
      functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
        "rel-t8-ns",
        validOrderPayload({ status: "ready" }),
        validOrderPayload({ status: "no_show" }),
      )),
    ]);
    const s = await userReliability();
    assert.equal(s.eligibleOrders, 2);
    assert.equal(s.collectedOrders, 1);
    assert.equal(s.noShowOrders, 1);
    // Both orders are marked processed.
    for (const id of ["rel-t8-col", "rel-t8-ns"]) {
      const order = await db.collection("orders").doc(id).get();
      assert.equal(order.data().reliabilityProcessed, true, id);
    }
  });
});

describe("Pickup reliability — non-eligible orders (Tests 9, 10)", () => {
  it("Test 9 — a cancelled order never affects reliability", async () => {
    await seedOrder("rel-t9-1", validOrderPayload({ status: "cancelled" }));
    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "rel-t9-1",
      validOrderPayload({ status: "pending" }),
      validOrderPayload({ status: "cancelled" }),
    ));
    assert.equal(await userReliability(), undefined);
  });

  it("Test 10 — a READY order never affects reliability", async () => {
    await fireTerminal("rel-t10-1", "collected");
    await seedOrder("rel-t10-2", validOrderPayload({ status: "ready" }));
    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "rel-t10-2",
      validOrderPayload({ status: "preparing" }),
      validOrderPayload({ status: "ready" }),
    ));
    const s = await userReliability();
    assert.equal(s.eligibleOrders, 1, "only the collected order counted");
  });
});

describe("Pickup reliability — weighted score (Test 13)", () => {
  it("Example C — 60/60 → score 60, NEEDS_IMPROVEMENT", async () => {
    const sequence = ["collected", "collected", "no_show", "collected", "no_show"];
    for (let i = 0; i < sequence.length; i++) {
      await fireTerminal(`rel-t13a-${i}`, sequence[i]);
    }
    const s = await userReliability();
    assert.equal(s.collectionRate, 60);
    assert.equal(s.recentCollectionRate, 60);
    assert.equal(s.reliabilityScore, 60);
    assert.equal(s.status, "NEEDS_IMPROVEMENT");
  });

  it("Example — 17/21 lifetime (≈81) / 60 recent → score 74.7, "
      + "NEEDS_IMPROVEMENT", async () => {
    // 21 events: the last 10 are 6 collected + 4 no-show (recent rate 60).
    // Lifetime: 17 collected / 21 eligible = 80.95… → roundRate → 81.0.
    for (let i = 0; i < 21; i++) {
      const recent10 = i >= 11;
      const noShow = recent10 && (i - 11) < 4;
      await fireTerminal(`rel-t13x-${i}`, noShow ? "no_show" : "collected");
    }
    const s = await userReliability();
    assert.equal(s.eligibleOrders, 21);
    assert.equal(s.collectedOrders, 17);
    assert.equal(s.noShowOrders, 4);
    assert.equal(s.collectionRate, 81.0, "17/21 lifetime rounded to 81.0");
    assert.equal(s.recentCollectionRate, 60);
    // Score = 81.0*0.7 + 60*0.3 = 74.7 → just below GOOD (75) →
    // NEEDS_IMPROVEMENT.
    assert.equal(s.reliabilityScore, 74.7);
    assert.equal(s.status, "NEEDS_IMPROVEMENT");
  });

  it("AGENTS.md Example D — 94 lifetime / 60 recent → score 83.8, GOOD",
      async () => {
    // 100 events: first 90 are 88 collected + 2 no-show; the last 10 are
    // 6 collected + 4 no-show. Lifetime: 94 collected / 100 eligible →
    // 94.0. Recent window (last 10): 6 collected / 10 → 60.
    // Score = 94.0*0.7 + 60*0.3 = 83.8 → GOOD.
    for (let i = 0; i < 100; i++) {
      let noShow;
      if (i < 90) {
        noShow = i >= 88; // 2 no-shows among the first 90
      } else {
        noShow = (i - 90) < 4; // 4 no-shows in the recent 10
      }
      await fireTerminal(`rel-t13d-${i}`, noShow ? "no_show" : "collected");
    }
    const s = await userReliability();
    assert.equal(s.eligibleOrders, 100);
    assert.equal(s.collectedOrders, 94);
    assert.equal(s.noShowOrders, 6);
    assert.equal(s.collectionRate, 94);
    assert.equal(s.recentCollectionRate, 60);
    // 94*0.7 + 60*0.3 = 65.8 + 18 = 83.8 → GOOD (75-89).
    assert.equal(s.reliabilityScore, 83.8);
    assert.equal(s.status, "GOOD");
  });

  it("a 3+ eligible EXCELLENT record is classified EXCELLENT", async () => {
    for (let i = 0; i < 3; i++) {
      await fireTerminal(`rel-t13e-${i}`, "collected");
    }
    const s = await userReliability();
    assert.equal(s.collectionRate, 100);
    assert.equal(s.reliabilityScore, 100);
    assert.equal(s.status, "EXCELLENT");
  });
});

describe("Pickup reliability — missing user doc (deferred, never dropped)", () => {
  it("defers the event when the user doc is missing, then counts it once "
      + "the user doc appears", async () => {
    const ghostId = "ghost-student";
    // seedUsers() only creates student1/admin1 — users/ghost-student does
    // NOT exist, so the reliability engine must defer rather than drop.
    await seedOrder("rel-defer-1", validOrderPayload({
      studentId: ghostId,
      status: "collected",
    }));

    // First delivery: user doc missing → the handler rejects with a
    // retriable deferral error, records a pending marker, and does NOT set
    // reliabilityProcessed (the event must stay countable).
    await assert.rejects(
      functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
        "rel-defer-1",
        validOrderPayload({ studentId: ghostId, status: "ready" }),
        validOrderPayload({ studentId: ghostId, status: "collected" }),
      )),
      /deferred/,
    );

    let order = await db.collection("orders").doc("rel-defer-1").get();
    assert.equal(order.data().reliabilityPending, true);
    assert.ok(
      order.data().reliabilityPendingSince instanceof admin.firestore.Timestamp,
      "pendingSince recorded",
    );
    assert.equal(
      order.data().reliabilityProcessed,
      undefined,
      "order NOT permanently marked processed",
    );
    // The terminal timestamp is persisted BEFORE reliability processing, so
    // it is already written on the deferred first delivery; the redelivery
    // must not re-stamp (drift) it.
    const firstCollectedAt = order.data().collectedAt;
    assert.ok(
      firstCollectedAt instanceof admin.firestore.Timestamp,
      "collectedAt persisted on the first (deferred) delivery",
    );

    // The user doc is created/restored later.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc(ghostId).set({
        fullName: "Ghost Student",
        email: "ghost@test.com",
        role: "student",
        accountStatus: "ACTIVE",
        createdAt: new Date(),
      });
    });

    // Retry (as Cloud Functions redelivers the event): build the event
    // WITHOUT re-setting the order document, so the pending marker is
    // preserved; the retry now counts the event normally.
    const ref = db.collection("orders").doc("rel-defer-1");
    const snapshot = (data) => ({ ref, data: () => data, exists: true });
    await functionsModule.onOrderStatusChanged.run({
      data: {
        before: snapshot(validOrderPayload({ studentId: ghostId, status: "ready" })),
        after: snapshot(validOrderPayload({ studentId: ghostId, status: "collected" })),
      },
      params: { orderId: "rel-defer-1" },
    });

    order = await db.collection("orders").doc("rel-defer-1").get();
    assert.equal(
      order.data().collectedAt.toMillis(),
      firstCollectedAt.toMillis(),
      "redelivery preserved the persisted collectedAt (no drift)",
    );

    const s = (await db.collection("users").doc(ghostId).get())
      .data().pickupReliability;
    assert.equal(s.eligibleOrders, 1, "deferred event counted after user doc appears");
    assert.equal(s.collectedOrders, 1);
    order = await db.collection("orders").doc("rel-defer-1").get();
    assert.equal(order.data().reliabilityProcessed, true);
    assert.equal(
      order.data().reliabilityPending,
      undefined,
      "pending marker cleared after the event counted",
    );
  });

  it("gives up explicitly and audibly (MISSING_USER) after the retry window",
      async () => {
    const ghostId = "ghost-student-2";
    // A Date is accepted by both the client-SDK seedOrder fixture and the
    // Admin-SDK handler, and is read back as an admin Timestamp by the
    // engine (which is what deferReliabilityEvent checks).
    const oldPendingSince = new Date(
      Date.now() - (7 * 24 * 60 * 60 * 1000 + 60 * 1000),
    );
    const afterData = validOrderPayload({
      studentId: ghostId,
      status: "collected",
      reliabilityPending: true,
      reliabilityPendingSince: oldPendingSince,
    });
    await seedOrder("rel-skip-1", afterData);

    // No throw: the engine records an explicit, auditable skip and returns.
    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "rel-skip-1",
      validOrderPayload({ studentId: ghostId, status: "ready" }),
      afterData,
    ));

    const order = await db.collection("orders").doc("rel-skip-1").get();
    assert.equal(order.data().reliabilityProcessed, true);
    assert.equal(order.data().reliabilitySkippedReason, "MISSING_USER");
    assert.ok(
      order.data().reliabilitySkippedAt instanceof admin.firestore.Timestamp,
      "skip timestamp recorded",
    );
    const user = await db.collection("users").doc(ghostId).get();
    assert.equal(user.exists, false, "no summary written for a skipped event");
  });

  it("denies clients forging deferral/skip markers on an order", async () => {
    await seedOrder("rel-forge-2", validOrderPayload({ status: "ready" }));
    const adminDb = testEnv.authenticatedContext("admin1").firestore();
    for (const field of [
      "reliabilityPending",
      "reliabilityPendingSince",
      "reliabilitySkippedReason",
      "reliabilitySkippedAt",
    ]) {
      await assert.rejects(
        adminDb.collection("orders").doc("rel-forge-2")
          .update({ status: "ready", [field]: true }),
        /PERMISSION_DENIED/,
        `${field} must be server-authoritative`,
      );
    }
  });

  it("scheduled reconciliation counts a deferred event once the user doc "
      + "appears (no reliance on the trigger retry window)", async () => {
    const ghostId = "ghost-student-3";
    // A pending order whose user doc still does not exist.
    await seedOrder("rel-reconcile-1", validOrderPayload({
      studentId: ghostId,
      status: "collected",
      reliabilityPending: true,
      reliabilityPendingSince: new Date(Date.now() - 60 * 1000),
    }));

    // First scheduled run: user doc still missing → stays pending.
    await functionsModule.processExpiredPickups.run({});
    let order = await db.collection("orders").doc("rel-reconcile-1").get();
    assert.equal(order.data().reliabilityPending, true, "still pending");
    assert.equal(order.data().reliabilityProcessed, undefined);

    // The user doc is restored.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc(ghostId).set({
        fullName: "Ghost Student 3",
        email: "ghost3@test.com",
        role: "student",
        accountStatus: "ACTIVE",
        createdAt: new Date(),
      });
    });

    // Second scheduled run: the event is counted and the marker cleared.
    await functionsModule.processExpiredPickups.run({});
    order = await db.collection("orders").doc("rel-reconcile-1").get();
    assert.equal(order.data().reliabilityProcessed, true, "counted by reconcile");
    // The reconcile path shares processReliabilityEvent, so it persists the
    // counted outcome immutably just like the trigger path.
    assert.equal(order.data().reliabilityOutcome, "COLLECTED");
    assert.equal(order.data().reliabilityPending, undefined, "marker cleared");
    const s = (await db.collection("users").doc(ghostId).get())
      .data().pickupReliability;
    assert.equal(s.eligibleOrders, 1);
    assert.equal(s.collectedOrders, 1);
  });

  it("scheduled reconciliation gives up explicitly after the retry window",
      async () => {
    const ghostId = "ghost-student-4";
    // A pending order whose retry window has already elapsed.
    await seedOrder("rel-reconcile-skip-1", validOrderPayload({
      studentId: ghostId,
      status: "no_show",
      reliabilityPending: true,
      reliabilityPendingSince: new Date(
        Date.now() - (7 * 24 * 60 * 60 * 1000 + 60 * 1000),
      ),
    }));

    await functionsModule.processExpiredPickups.run({});
    const order = await db
      .collection("orders").doc("rel-reconcile-skip-1").get();
    assert.equal(order.data().reliabilityProcessed, true);
    assert.equal(order.data().reliabilitySkippedReason, "MISSING_USER");
    assert.ok(
      order.data().reliabilitySkippedAt instanceof admin.firestore.Timestamp,
      "skip timestamp recorded",
    );
    assert.equal(
      order.data().reliabilityPending,
      undefined,
      "pending marker cleared after give-up",
    );
  });
});

describe("Order foodIds backfill — transactional, never clobbers", () => {
  it("backfills foodIds on a legacy order that lacks the field", async () => {
    await seedOrder("bf-legacy", validOrderPayload({ status: "collected" }));
    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "bf-legacy",
      validOrderPayload({ status: "ready" }),
      validOrderPayload({ status: "collected" }),
    ));
    const order = await db.collection("orders").doc("bf-legacy").get();
    assert.deepEqual(
      order.data().foodIds,
      ["food_1"],
      "derived from the nested items data",
    );
  });

  it("never overwrites an existing empty foodIds list", async () => {
    await seedOrder(
      "bf-empty",
      validOrderPayload({ status: "collected", foodIds: [] }),
    );
    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "bf-empty",
      validOrderPayload({ status: "ready", foodIds: [] }),
      validOrderPayload({ status: "collected", foodIds: [] }),
    ));
    const order = await db.collection("orders").doc("bf-empty").get();
    assert.deepEqual(order.data().foodIds, [], "empty list preserved");
  });

  it("never overwrites a malformed foodIds value", async () => {
    await seedOrder(
      "bf-malformed",
      validOrderPayload({ status: "collected", foodIds: "garbage" }),
    );
    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "bf-malformed",
      validOrderPayload({ status: "ready", foodIds: "garbage" }),
      validOrderPayload({ status: "collected", foodIds: "garbage" }),
    ));
    const order = await db.collection("orders").doc("bf-malformed").get();
    assert.equal(
      order.data().foodIds,
      "garbage",
      "malformed historical value preserved",
    );
  });
});
