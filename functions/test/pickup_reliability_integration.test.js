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

  it("denies an admin who tries to forge reliabilityProcessed on an order", async () => {
    await seedOrder("rel-forge-1", validOrderPayload({ status: "ready" }));
    await assert.rejects(
      testEnv.authenticatedContext("admin1").firestore()
        .collection("orders").doc("rel-forge-1")
        .update({ status: "ready", reliabilityProcessed: true }),
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
