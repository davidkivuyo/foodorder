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

// Phase E — GRADUATED ORDERING RESTRICTIONS: executable emulator coverage.
//
// This suite runs the REAL Firestore emulator with the REAL firestore.rules
// loaded and exercises the REAL exported `placeOrder` callable and the
// reliability engine (via `onOrderStatusChanged`) against the emulator-backed
// Admin SDK, complementing the static guardrails in
// test/phase_e_foundation_test.dart.
//
// It covers AGENTS.md Phase E section 36, Tests 1-15:
//   1  New user            2  Good reliability      3  Needs improvement
//   4  Poor → LIMITED      5  Critical → HIGHLY     6  Insufficient history
//   7  2 active → rejected 8  1 active → rejected   9  Collected frees a slot
//  10  No-show frees slot  11 CANCELLED excluded    12 Recovery
//  13 Student manipulation 14 Concurrent attempts   15 Backend unavailable
//
// Run (requires Java 21+ — e.g. JAVA_HOME=/usr/lib/jvm/java-25-openjdk):
//   npm run test:phase-e:integration   (inside functions/)

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

/** Payload the Flutter client sends to the placeOrder callable. */
function placeOrderPayload(overrides = {}) {
  return {
    orderId: "CB-E100",
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
    foodIds: ["food_1"],
    price: 3000,
    cafeId: "cafe1",
    cafeLocation: null,
    distanceMeters: 200,
    distanceCalculated: false,
    pickupWindowMinutes: 20,
    ...overrides,
  };
}

/** Build the request shape consumed by an onCall handler. */
function callableRequest(uid, data, token = { email_verified: true }) {
  return { auth: { uid, token }, data };
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

async function seedFoodItems() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("food_items").doc("food_1").set({
      id: "food_1",
      title: "Rice & Beans",
      price: 3000,
      available: true,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await ctx.firestore().collection("food_items").doc("food_unavailable").set({
      id: "food_unavailable",
      title: "Sold Out",
      price: 2000,
      available: false,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });
}

/** Seed a server-maintained reliability summary on a user document. */
async function seedReliability(uid, summary) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("users").doc(uid).update({
      pickupReliability: summary,
    });
  });
}

function studentDb(uid = "student1") {
  return testEnv.authenticatedContext(uid, { email_verified: true }).firestore();
}

function adminDb() {
  return testEnv.authenticatedContext("admin1").firestore();
}

async function orderById(orderId) {
  const snap = await db.collection("orders").doc(orderId).get();
  return snap.exists ? snap.data() : null;
}

async function userSummary(uid = "student1") {
  const snap = await db.collection("users").doc(uid).get();
  return snap.exists ? snap.data().pickupReliability : undefined;
}

async function makeStatusChangeEvent(orderId, beforeData, afterData) {
  const ref = db.collection("orders").doc(orderId);
  await ref.set(afterData);
  const snapshot = (data) => ({ ref, data: () => data, exists: true });
  return {
    data: { before: snapshot(beforeData), after: snapshot(afterData) },
    params: { orderId },
  };
}

async function fireTerminal(orderId, status) {
  await seedOrder(orderId, validOrderPayload({ status }));
  await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
    orderId,
    validOrderPayload({ status: "ready" }),
    validOrderPayload({ status }),
  ));
}

/** Expected restriction level for a stored summary (mirrors restrictionFor). */
function expectedLevel(summary) {
  if (!summary || (summary.eligibleOrders || 0) < 3) return "NORMAL";
  const score = summary.reliabilityScore;
  if (score >= 50) return "NORMAL";
  if (score >= 25) return "LIMITED";
  return "HIGHLY_LIMITED";
}

async function placeOrder(uid, payload) {
  return functionsModule.placeOrder.run(callableRequest(uid, payload));
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
  await seedFoodItems();
});

after(async () => {
  await testEnv.cleanup();
});

describe("Phase E — restriction engine (derived server-side, no extra writes)", () => {
  it("stores restrictionLevel/restrictionReason on every reliability summary", async () => {
    await fireTerminal("pe-flow-1", "no_show");
    let s = await userSummary();
    assert.equal(s.eligibleOrders, 1);
    assert.equal(s.restrictionLevel, "NORMAL", "insufficient history → NORMAL");
    assert.equal(s.restrictionReason, null);

    // Drive the score below 25 with 3+ eligible orders → HIGHLY_LIMITED.
    await fireTerminal("pe-flow-2", "no_show");
    await fireTerminal("pe-flow-3", "no_show");
    s = await userSummary();
    assert.equal(s.eligibleOrders, 3);
    assert.equal(s.noShowOrders, 3);
    assert.equal(s.restrictionLevel, expectedLevel(s));
    assert.equal(s.restrictionLevel, "HIGHLY_LIMITED", "0% → CRITICAL");
    assert.equal(s.restrictionReason, "Very low pickup reliability");
  });

  it("recovery — restriction follows the current score (no manual intervention)", async () => {
    // POOR baseline (2 collected + 1 no-show of 3 eligible).
    await seedReliability("student1", {
      eligibleOrders: 3,
      collectedOrders: 2,
      noShowOrders: 1,
      collectionRate: 66.7,
      recentEligibleOrders: 3,
      recentCollectedOrders: 2,
      recentNoShowOrders: 1,
      recentCollectionRate: 66.7,
      reliabilityScore: 40,
      status: "POOR",
      restrictionLevel: "LIMITED",
      restrictionReason: "Low pickup reliability",
    });
    let s = await userSummary();
    assert.equal(s.restrictionLevel, "LIMITED");

    // Four clean collections push the weighted score above 50 → NORMAL.
    for (let i = 0; i < 4; i++) {
      await fireTerminal(`pe-rec-${i}`, "collected");
    }
    s = await userSummary();
    assert.equal(s.eligibleOrders, 7);
    assert.ok(s.reliabilityScore >= 50, `score ${s.reliabilityScore} recovered`);
    assert.equal(s.restrictionLevel, "NORMAL", "recovered automatically");
    assert.equal(s.restrictionReason, null);
  });
});

describe("Phase E — placeOrder callable (Tests 1-6: restriction levels)", () => {
  it("Test 1 — new user (no summary) is unrestricted and can order", async () => {
    const result = await placeOrder("student1", placeOrderPayload({ orderId: "CB-T1" }));
    assert.equal(result.orderId, "CB-T1");
    const order = await orderById("CB-T1");
    assert.equal(order.studentId, "student1");
    assert.equal(order.status, "pending");
    assert.equal(order.deadlineStatus, "NOT_READY");
  });

  it("Test 2 — score 95 (EXCELLENT) → NORMAL, orders allowed", async () => {
    await seedReliability("student1", {
      eligibleOrders: 10, collectedOrders: 10, noShowOrders: 0,
      reliabilityScore: 95, status: "EXCELLENT",
    });
    const result = await placeOrder("student1", placeOrderPayload({ orderId: "CB-T2" }));
    assert.equal(result.orderId, "CB-T2");
  });

  it("Test 3 — score 65 (NEEDS_IMPROVEMENT) → NORMAL, no limit yet", async () => {
    await seedReliability("student1", {
      eligibleOrders: 5, collectedOrders: 3, noShowOrders: 2,
      reliabilityScore: 65, status: "NEEDS_IMPROVEMENT",
    });
    const result = await placeOrder("student1", placeOrderPayload({ orderId: "CB-T3" }));
    assert.equal(result.orderId, "CB-T3");
  });

  it("Test 4 — score 40 (POOR) → LIMITED with 2 active orders; third rejected", async () => {
    await seedReliability("student1", {
      eligibleOrders: 3, collectedOrders: 2, noShowOrders: 1,
      reliabilityScore: 40, status: "POOR",
    });
    // Two active orders already in flight.
    await seedOrder("CB-T4-a", validOrderPayload({ status: "pending" }));
    await seedOrder("CB-T4-b", validOrderPayload({ status: "ready" }));

    // Third order → rejected with the stable ACTIVE_ORDER_LIMIT sub-code.
    await assert.rejects(
      placeOrder("student1", placeOrderPayload({ orderId: "CB-T4-x" })),
      (err) => {
        assert.equal(err.code, "failed-precondition");
        assert.equal(err.details.code, "ACTIVE_ORDER_LIMIT");
        assert.equal(err.details.activeOrderLimit, 2);
        return true;
      },
    );
    assert.equal(await orderById("CB-T4-x"), null, "order was NOT created");
  });

  it("Test 5 — score 20 (CRITICAL) → HIGHLY_LIMITED with 1 active order; second rejected", async () => {
    await seedReliability("student1", {
      eligibleOrders: 3, collectedOrders: 0, noShowOrders: 3,
      reliabilityScore: 20, status: "CRITICAL",
    });
    await seedOrder("CB-T5-a", validOrderPayload({ status: "accepted" }));

    await assert.rejects(
      placeOrder("student1", placeOrderPayload({ orderId: "CB-T5-x" })),
      (err) => {
        assert.equal(err.code, "failed-precondition");
        assert.equal(err.details.code, "ACTIVE_ORDER_LIMIT");
        assert.equal(err.details.activeOrderLimit, 1);
        return true;
      },
    );
    assert.equal(await orderById("CB-T5-x"), null);
  });

  it("Test 6 — insufficient history (1 eligible, low score) → NORMAL", async () => {
    await seedReliability("student1", {
      eligibleOrders: 1, collectedOrders: 0, noShowOrders: 1,
      reliabilityScore: 5, status: "CRITICAL",
    });
    const result = await placeOrder("student1", placeOrderPayload({ orderId: "CB-T6" }));
    assert.equal(result.orderId, "CB-T6");
  });

  it("a LIMITED student below the limit can still place an order", async () => {
    await seedReliability("student1", {
      eligibleOrders: 3, collectedOrders: 2, noShowOrders: 1,
      reliabilityScore: 40, status: "POOR",
    });
    await seedOrder("CB-T4-1", validOrderPayload({ status: "pending" }));
    const result = await placeOrder("student1", placeOrderPayload({ orderId: "CB-T4-2" }));
    assert.equal(result.orderId, "CB-T4-2", "1 active of 2 allowed");
  });
});

describe("Phase E — active-order lifecycle frees slots (Tests 9-11)", () => {
  it("Test 9 — a LIMITED student's COLLECTED order frees an active slot", async () => {
    await seedReliability("student1", {
      eligibleOrders: 3, collectedOrders: 2, noShowOrders: 1,
      reliabilityScore: 40, status: "POOR",
    });
    await seedOrder("CB-T9-a", validOrderPayload({ status: "pending" }));
    await seedOrder("CB-T9-b", validOrderPayload({ status: "ready" }));

    // At the limit: rejected.
    await assert.rejects(
      placeOrder("student1", placeOrderPayload({ orderId: "CB-T9-x" })),
      (err) => err.details && err.details.code === "ACTIVE_ORDER_LIMIT",
    );

    // One active order is collected → slot freed → order allowed.
    await seedOrder("CB-T9-b", validOrderPayload({ status: "collected" }));
    const result = await placeOrder("student1", placeOrderPayload({ orderId: "CB-T9-c" }));
    assert.equal(result.orderId, "CB-T9-c");
  });

  it("Test 10 — a NO_SHOW order stops counting and reliability/restriction update", async () => {
    await seedReliability("student1", {
      eligibleOrders: 3, collectedOrders: 0, noShowOrders: 3,
      reliabilityScore: 20, status: "CRITICAL",
    });
    await seedOrder("CB-T10-a", validOrderPayload({ status: "ready" }));

    // At the limit (1 active of 1 allowed): rejected.
    await assert.rejects(
      placeOrder("student1", placeOrderPayload({ orderId: "CB-T10-x" })),
      (err) => err.details && err.details.code === "ACTIVE_ORDER_LIMIT",
    );

    // The order becomes NO_SHOW (reliability engine updates the summary).
    await seedOrder("CB-T10-a", validOrderPayload({
      status: "no_show", expiredAt: new Date(),
    }));
    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "CB-T10-a",
      validOrderPayload({ status: "ready" }),
      validOrderPayload({ status: "no_show", expiredAt: new Date() }),
    ));

    const s = await userSummary();
    assert.equal(s.eligibleOrders, 4, "reliability updated");
    assert.equal(s.noShowOrders, 4);

    // NO_SHOW no longer counts toward the active limit → order allowed.
    const result = await placeOrder("student1", placeOrderPayload({ orderId: "CB-T10-b" }));
    assert.equal(result.orderId, "CB-T10-b");
  });

  it("Test 11 — a CANCELLED order never counts toward the active limit", async () => {
    await seedReliability("student1", {
      eligibleOrders: 3, collectedOrders: 2, noShowOrders: 1,
      reliabilityScore: 40, status: "POOR",
    });
    // Two CANCELLED orders (terminal, excluded from the active count).
    await seedOrder("CB-T11-a", validOrderPayload({ status: "cancelled" }));
    await seedOrder("CB-T11-b", validOrderPayload({ status: "cancelled" }));
    const result = await placeOrder("student1", placeOrderPayload({ orderId: "CB-T11-c" }));
    assert.equal(result.orderId, "CB-T11-c", "cancelled orders do not consume slots");
  });
});

describe("Phase E — security (Tests 13, 37)", () => {
  it("Test 13 — a student cannot write pickupReliability / restrictionLevel", async () => {
    await seedReliability("student1", {
      eligibleOrders: 3, collectedOrders: 0, noShowOrders: 3,
      reliabilityScore: 20, status: "CRITICAL",
      restrictionLevel: "HIGHLY_LIMITED",
      restrictionReason: "Very low pickup reliability",
    });
    await assert.rejects(
      studentDb().collection("users").doc("student1").update({
        pickupReliability: { restrictionLevel: "NORMAL" },
      }),
      /PERMISSION_DENIED/,
    );
    // Defence-in-depth: even a favourite-list update cannot smuggle it.
    await assert.rejects(
      studentDb().collection("users").doc("student1").update({
        favoriteMenu: [],
        favoriteMenuUpdatedAt: new Date(),
        pickupReliability: { restrictionLevel: "NORMAL" },
      }),
      /PERMISSION_DENIED/,
    );
    const s = await userSummary();
    assert.equal(
      s.restrictionLevel,
      "HIGHLY_LIMITED",
      "restriction level unchanged after the write attack",
    );
    assert.equal(
      s.restrictionReason,
      "Very low pickup reliability",
      "restriction reason unchanged after the write attack",
    );
  });

  it("an admin cannot arbitrarily modify a student's restriction fields", async () => {
    await seedReliability("student1", {
      eligibleOrders: 3, collectedOrders: 0, noShowOrders: 3,
      reliabilityScore: 20, status: "CRITICAL",
      restrictionLevel: "HIGHLY_LIMITED",
    });
    await assert.rejects(
      adminDb().collection("users").doc("student1").update({
        pickupReliability: { restrictionLevel: "NORMAL" },
      }),
      /PERMISSION_DENIED/,
    );
    const s = await userSummary();
    assert.equal(s.restrictionLevel, "HIGHLY_LIMITED", "admin could not change it");
  });

  it("a student cannot create an order for another user's account", async () => {
    await assert.rejects(
      placeOrder("student1", placeOrderPayload({
        orderId: "CB-FORGE", studentId: "other-user",
      })),
      (err) => err.code === "permission-denied",
    );
    assert.equal(await orderById("CB-FORGE"), null);
  });
});

describe("Phase E — concurrency & failure handling (Tests 14, 15)", () => {
  it("Test 14 — concurrent order attempts cannot bypass the active-order limit", async () => {
    await seedReliability("student1", {
      eligibleOrders: 3, collectedOrders: 0, noShowOrders: 3,
      reliabilityScore: 20, status: "CRITICAL",
    });
    // 0 active orders, limit 1 → two simultaneous attempts: exactly one wins.
    const attempts = await Promise.allSettled([
      placeOrder("student1", placeOrderPayload({ orderId: "CB-RACE-1" })),
      placeOrder("student1", placeOrderPayload({ orderId: "CB-RACE-2" })),
    ]);
    const fulfilled = attempts.filter((a) => a.status === "fulfilled");
    const rejected = attempts.filter((a) => a.status === "rejected");
    assert.equal(fulfilled.length, 1, "exactly one order created");
    assert.equal(rejected.length, 1, "exactly one attempt rejected");
    assert.equal(
      rejected[0].reason.details.code,
      "ACTIVE_ORDER_LIMIT",
      "loser rejected with the limit sub-code",
    );
    const created = await db.collection("orders")
      .where("studentId", "==", "student1")
      .get();
    assert.equal(created.size, 1, "only one order document exists");
  });

  it("Test 15 — backend cannot verify (missing user doc) → order NOT created", async () => {
    // users/ghost does not exist (seedUsers only creates student1/admin1).
    await assert.rejects(
      placeOrder("ghost", placeOrderPayload({
        orderId: "CB-GHOST", studentId: "ghost",
      })),
      (err) => err.code === "unavailable",
    );
    assert.equal(await orderById("CB-GHOST"), null, "fail-safe: order not created");
  });

  it("a suspended student cannot place an order", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc("student1").update({
        accountStatus: "SUSPENDED",
      });
    });
    await assert.rejects(
      placeOrder("student1", placeOrderPayload({ orderId: "CB-SUSP" })),
      (err) => err.code === "permission-denied",
    );
    assert.equal(await orderById("CB-SUSP"), null);
  });

  it("unavailable food items reject the order server-side", async () => {
    await assert.rejects(
      placeOrder("student1", placeOrderPayload({
        orderId: "CB-UNAVAIL",
        items: [{
          foodItemId: "food_unavailable",
          title: "Sold Out",
          price: 2000,
          quantity: 1,
          image: "",
          selectedCafe: "Cafe A",
        }],
        foodIds: ["food_unavailable"],
        price: 2000,
      })),
      (err) => err.code === "failed-precondition"
        && err.details.code === "ITEMS_UNAVAILABLE",
    );
    assert.equal(await orderById("CB-UNAVAIL"), null);
  });
});
