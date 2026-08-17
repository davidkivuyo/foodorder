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

// Phase G — ADMIN INTERVENTION (excuseNoShow): executable emulator coverage.
//
// This suite runs the REAL Firestore emulator with the REAL firestore.rules
// loaded and exercises the REAL exported `excuseNoShow` callable against the
// emulator-backed Admin SDK, complementing the static guardrails in the
// Flutter foundation tests.
//
// It covers AGENTS.md Phase G section 36, Tests 1-14:
//   1  Valid no-show eligible      2  Excuse + reliability recalculation
//   3  Already excused (idempotent) 4  Wrong status (READY) rejected
//   5  Collected order rejected     6  Cancelled order rejected
//   7  Unauthorized admin (cross-cafe)  8  Student attempt denied
//   9  Lifetime metric correction  10 Restriction recovery
//  11  Recent history correction   12 Notification (once, deduped)
//  13  Audit log (once, immutable) 14 Concurrent admin actions
//
// Run (requires Java 21+ — e.g. JAVA_HOME=/usr/lib/jvm/java-25-openjdk):
//   npm run test:excuse:integration   (inside functions/)

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
    cafes: ["Cafe A"],
    ...overrides,
  };
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
      cafeName: "Cafe A",
      accountStatus: "ACTIVE",
      strikeCount: 0,
      strikePercentage: 0,
      createdAt: new Date(),
    });
    await seed.collection("users").doc("admin2").set({
      fullName: "Admin Two",
      email: "admin2@test.com",
      role: "admin",
      cafeName: "Cafe B",
      accountStatus: "ACTIVE",
      strikeCount: 0,
      strikePercentage: 0,
      createdAt: new Date(),
    });
    await seed.collection("users").doc("suspendedAdmin").set({
      fullName: "Suspended Admin",
      email: "suspended@test.com",
      role: "admin",
      cafeName: "Cafe A",
      accountStatus: "SUSPENDED",
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

async function seedReliability(uid, summary) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("users").doc(uid).update({
      pickupReliability: summary,
    });
  });
}

/** Fire a real NO_SHOW terminal event so the reliability engine counts it. */
async function fireNoShow(orderId) {
  // Mirrors the scheduled no-show processor: the no_show transition carries
  // the authoritative noShowAt/expiredAt timestamps (the excuse eligibility
  // check requires noShowAt to exist).
  await seedOrder(orderId, validOrderPayload({
    status: "no_show",
    noShowAt: new Date(),
    expiredAt: new Date(),
  }));
  await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
    orderId,
    validOrderPayload({ status: "ready" }),
    validOrderPayload({
      status: "no_show",
      noShowAt: new Date(),
      expiredAt: new Date(),
    }),
  ));
}

function callableRequest(uid, data, token = { email_verified: true }) {
  return { auth: { uid, token }, data };
}

function excuseNoShow(uid, data) {
  return functionsModule.excuseNoShow.run(callableRequest(uid, data));
}

async function userReliability(uid = "student1") {
  const snap = await db.collection("users").doc(uid).get();
  return snap.exists ? snap.data().pickupReliability : undefined;
}

async function orderById(orderId) {
  const snap = await db.collection("orders").doc(orderId).get();
  return snap.exists ? snap.data() : null;
}

async function countNotifications(orderId) {
  const snaps = await db
    .collection("notifications")
    .where("eventId", "==", `NO_SHOW_EXCUSED_${orderId}`)
    .get();
  return snaps.size;
}

async function auditLog(orderId) {
  const snap = await db
    .collection("audit_logs")
    .doc(`NO_SHOW_EXCUSED_${orderId}`)
    .get();
  return snap.exists ? snap.data() : null;
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

describe("Phase G — excuseNoShow eligibility & authorization (Tests 1, 4-8)", () => {
  it("Test 1 — a valid unexcused NO_SHOW can be excused", async () => {
    await fireNoShow("g-valid-1");
    const result = await excuseNoShow("admin1", {
      orderId: "g-valid-1",
      reason: "Student reported emergency",
    });
    assert.equal(result.success, true);

    const order = await orderById("g-valid-1");
    assert.equal(order.status, "no_show", "order stays NO_SHOW");
    assert.equal(order.noShowExcused, true);
    assert.equal(order.excuseReason, "Student reported emergency");
    assert.ok(order.excusedAt, "excusedAt recorded");
    assert.equal(order.excusedBy, "admin1");
    assert.equal(order.excuseNote, null);
    assert.equal(order.noShowAt instanceof admin.firestore.Timestamp, true,
      "original noShowAt preserved");
  });

  it("Test 4 — a READY order cannot be excused", async () => {
    await seedOrder("g-ready-1", validOrderPayload({ status: "ready" }));
    await assert.rejects(
      excuseNoShow("admin1", {
        orderId: "g-ready-1",
        reason: "Other",
        note: "test note",
      }),
      (err) => {
        assert.equal(err.code, "failed-precondition");
        assert.match(err.message, /Only no-show orders/);
        return true;
      },
    );
    const order = await orderById("g-ready-1");
    assert.equal(order.noShowExcused, undefined);
  });

  it("Test 5 — a COLLECTED order cannot be excused", async () => {
    await seedOrder("g-collected-1", validOrderPayload({ status: "collected" }));
    await assert.rejects(
      excuseNoShow("admin1", {
        orderId: "g-collected-1",
        reason: "Other",
        note: "test note",
      }),
      (err) => err.code === "failed-precondition",
    );
  });

  it("Test 6 — a CANCELLED order cannot be excused", async () => {
    await seedOrder("g-cancelled-1", validOrderPayload({ status: "cancelled" }));
    await assert.rejects(
      excuseNoShow("admin1", {
        orderId: "g-cancelled-1",
        reason: "Other",
        note: "test note",
      }),
      (err) => err.code === "failed-precondition",
    );
  });

  it("Test 7 — a Cafe B admin cannot excuse a Cafe A order", async () => {
    await fireNoShow("g-xcafe-1");
    await assert.rejects(
      excuseNoShow("admin2", {
        orderId: "g-xcafe-1",
        reason: "Other",
        note: "test note",
      }),
      (err) => {
        assert.equal(err.code, "permission-denied");
        assert.match(err.message, /not authorized to manage orders/i);
        return true;
      },
    );
    const order = await orderById("g-xcafe-1");
    assert.equal(order.noShowExcused, undefined, "nothing was written");
  });

  it("Test 8 — a student cannot excuse a no-show", async () => {
    await fireNoShow("g-student-1");
    await assert.rejects(
      excuseNoShow("student1", {
        orderId: "g-student-1",
        reason: "Other",
        note: "test note",
      }),
      (err) => err.code === "permission-denied",
    );
  });

  it("a suspended admin cannot excuse a no-show", async () => {
    await fireNoShow("g-susp-1");
    await assert.rejects(
      excuseNoShow("suspendedAdmin", {
        orderId: "g-susp-1",
        reason: "Other",
        note: "test note",
      }),
      (err) => err.code === "permission-denied",
    );
  });
});

describe("Phase G — reliability correction (Tests 2, 9-11)", () => {
  it("Test 2 — excusing recalculates reliability and excludes the event", async () => {
    // 2 collected + 1 no-show → POOR (score 40), then excuse the no-show.
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
      recentPickupHistory: [
        { orderId: "g-exc-1", outcome: "NO_SHOW", timestamp: new Date() },
        { orderId: "g-other-1", outcome: "COLLECTED", timestamp: new Date() },
        { orderId: "g-other-2", outcome: "COLLECTED", timestamp: new Date() },
      ],
    });
    // Mark the order as a counted no-show (the engine wrote these markers).
    await seedOrder("g-exc-1", validOrderPayload({
      status: "no_show",
      reliabilityProcessed: true,
      reliabilityOutcome: "NO_SHOW",
      noShowAt: new Date(),
    }));

    await excuseNoShow("admin1", {
      orderId: "g-exc-1",
      reason: "Student reported emergency",
      note: "Student was in an exam.",
    });

    const s = await userReliability();
    assert.equal(s.eligibleOrders, 2, "eligible decremented");
    assert.equal(s.noShowOrders, 0, "no-show excluded");
    assert.equal(s.collectedOrders, 2, "collected unchanged");
    assert.equal(s.recentEligibleOrders, 2, "recent window excludes the event");
    assert.equal(s.recentNoShowOrders, 0);
    assert.equal(s.recentCollectedOrders, 2);
    const historyOrderIds = s.recentPickupHistory.map((e) => e.orderId);
    assert.ok(!historyOrderIds.includes("g-exc-1"),
      "excused order omitted from recent history");
    assert.ok(historyOrderIds.includes("g-other-1"));
    assert.ok(historyOrderIds.includes("g-other-2"));
    // 100% collection rate → score 100; 2 eligible → INSUFFICIENT_HISTORY
    // (the minimum-history rule), restriction NORMAL (insufficient evidence).
    assert.equal(s.reliabilityScore, 100);
    assert.equal(s.status, "INSUFFICIENT_HISTORY");
    assert.equal(s.restrictionLevel, "NORMAL");
  });

  it("Test 9 — lifetime metric correction (eligible/noShow decrement, collected unchanged)", async () => {
    await seedReliability("student1", {
      eligibleOrders: 10,
      collectedOrders: 7,
      noShowOrders: 3,
      collectionRate: 70,
      recentEligibleOrders: 10,
      recentCollectedOrders: 7,
      recentNoShowOrders: 3,
      recentCollectionRate: 70,
      reliabilityScore: 70,
      status: "NEEDS_IMPROVEMENT",
      restrictionLevel: "NORMAL",
      restrictionReason: null,
    });
    await seedOrder("g-lifetime-1", validOrderPayload({
      status: "no_show",
      reliabilityProcessed: true,
      reliabilityOutcome: "NO_SHOW",
      noShowAt: new Date(),
    }));

    await excuseNoShow("admin1", {
      orderId: "g-lifetime-1",
      reason: "System/application issue",
    });

    const s = await userReliability();
    assert.equal(s.eligibleOrders, 9);
    assert.equal(s.noShowOrders, 2);
    assert.equal(s.collectedOrders, 7);
    // 7/9 lifetime rate; no recent history seeded → recent window is empty
    // (rate 100) → weighted score 0.7*77.8 + 0.3*100 = 84.4 → GOOD / NORMAL.
    assert.equal(s.reliabilityScore, 84.4, "weighted lifetime+recent rate");
    assert.equal(s.status, "GOOD");
    assert.equal(s.restrictionLevel, "NORMAL");
  });

  it("Test 10 — restriction recovery: LIMITED → NORMAL when the score crosses the threshold", async () => {
    // 5 eligible, 2 collected + 3 no-show → 40% → POOR → LIMITED. The
    // excused order (g-restrict-1) is one of the three no-shows.
    await seedReliability("student1", {
      eligibleOrders: 5,
      collectedOrders: 2,
      noShowOrders: 3,
      collectionRate: 40,
      recentEligibleOrders: 5,
      recentCollectedOrders: 2,
      recentNoShowOrders: 3,
      recentCollectionRate: 40,
      reliabilityScore: 40,
      status: "POOR",
      restrictionLevel: "LIMITED",
      restrictionReason: "Low pickup reliability",
      recentPickupHistory: [
        { orderId: "g-restrict-1", outcome: "NO_SHOW", timestamp: new Date() },
        { orderId: "g-restrict-2", outcome: "NO_SHOW", timestamp: new Date() },
        { orderId: "g-restrict-3", outcome: "NO_SHOW", timestamp: new Date() },
        { orderId: "g-restrict-4", outcome: "COLLECTED", timestamp: new Date() },
        { orderId: "g-restrict-5", outcome: "COLLECTED", timestamp: new Date() },
      ],
    });
    await seedOrder("g-restrict-1", validOrderPayload({
      status: "no_show",
      reliabilityProcessed: true,
      reliabilityOutcome: "NO_SHOW",
      noShowAt: new Date(),
    }));

    await excuseNoShow("admin1", {
      orderId: "g-restrict-1",
      reason: "Pickup information was incorrect",
    });

    const s = await userReliability();
    assert.equal(s.eligibleOrders, 4);
    assert.equal(s.noShowOrders, 2);
    assert.equal(s.collectedOrders, 2);
    // 2/4 lifetime AND 2/4 recent → weighted score exactly 50 →
    // NEEDS_IMPROVEMENT → NORMAL (score >= 50).
    assert.equal(s.reliabilityScore, 50);
    assert.equal(s.status, "NEEDS_IMPROVEMENT");
    assert.equal(s.restrictionLevel, "NORMAL", "recovered automatically");
    assert.equal(s.restrictionReason, null);
  });

  it("Test 11 — excusing an order present in recent history removes its NO_SHOW entry", async () => {
    await fireNoShow("g-history-1");
    let s = await userReliability();
    assert.equal(s.recentNoShowOrders, 1);
    assert.ok(s.recentPickupHistory.some((e) => e.orderId === "g-history-1"));

    await excuseNoShow("admin1", {
      orderId: "g-history-1",
      reason: "Admin-approved exception",
    });

    s = await userReliability();
    assert.equal(s.recentEligibleOrders, 0);
    assert.equal(s.recentNoShowOrders, 0);
    assert.ok(!s.recentPickupHistory.some((e) => e.orderId === "g-history-1"),
      "order removed from recent history");
  });

  it("an uncounted no-show (reliabilityProcessed missing) is excused without corrupting the summary", async () => {
    await seedReliability("student1", {
      eligibleOrders: 3,
      collectedOrders: 3,
      noShowOrders: 0,
      collectionRate: 100,
      recentEligibleOrders: 3,
      recentCollectedOrders: 3,
      recentNoShowOrders: 0,
      recentCollectionRate: 100,
      reliabilityScore: 100,
      status: "EXCELLENT",
      restrictionLevel: "NORMAL",
      restrictionReason: null,
    });
    // NO_SHOW order the engine never counted (deferred/skipped).
    await seedOrder("g-uncounted-1", validOrderPayload({
      status: "no_show",
      noShowAt: new Date(),
    }));

    await excuseNoShow("admin1", {
      orderId: "g-uncounted-1",
      reason: "Other",
      note: "System glitch",
    });

    const s = await userReliability();
    assert.equal(s.eligibleOrders, 3, "summary untouched — event was never counted");
    assert.equal(s.noShowOrders, 0);
    assert.equal(s.reliabilityScore, 100);
    const order = await orderById("g-uncounted-1");
    assert.equal(order.noShowExcused, true);
    assert.equal(order.excuseNote, "System glitch");
  });
});

describe("Phase G — idempotency, audit & notification (Tests 3, 12-14)", () => {
  it("Test 3 — an already-excused order cannot be excused again", async () => {
    await fireNoShow("g-double-1");
    await excuseNoShow("admin1", {
      orderId: "g-double-1",
      reason: "Student reported emergency",
    });

    await assert.rejects(
      excuseNoShow("admin1", {
        orderId: "g-double-1",
        reason: "Cafe unable to fulfill order",
      }),
      (err) => {
        assert.equal(err.code, "failed-precondition");
        assert.match(err.message, /already been excused/i);
        return true;
      },
    );

    // No duplicate audit log or notification.
    assert.equal(await countNotifications("g-double-1"), 1);
    const audit = await auditLog("g-double-1");
    assert.equal(audit.action, "NO_SHOW_EXCUSED");
    assert.equal(audit.reason, "Student reported emergency",
      "original reason preserved — no second audit record");
    const order = await orderById("g-double-1");
    assert.equal(order.excuseReason, "Student reported emergency");
  });

  it("Test 12 — exactly one student notification is created", async () => {
    await fireNoShow("g-notify-1");
    await excuseNoShow("admin1", {
      orderId: "g-notify-1",
      reason: "System/application issue",
    });
    assert.equal(await countNotifications("g-notify-1"), 1);

    // Repeated attempt → still exactly one (no duplicate).
    await assert.rejects(
      excuseNoShow("admin1", {
        orderId: "g-notify-1",
        reason: "Other",
        note: "test note",
      }),
      (err) => err.code === "failed-precondition",
    );
    assert.equal(await countNotifications("g-notify-1"), 1);

    const snaps = await db
      .collection("notifications")
      .where("eventId", "==", "NO_SHOW_EXCUSED_g-notify-1")
      .get();
    const notification = snaps.docs[0].data();
    assert.equal(notification.recipientId, "student1");
    assert.equal(notification.recipientRole, "student");
    assert.equal(notification.type, "NO_SHOW_EXCUSED");
    assert.equal(notification.orderId, "g-notify-1");
    assert.match(notification.message, /will not affect your pickup reliability/);
  });

  it("Test 13 — exactly one immutable audit log is created", async () => {
    await fireNoShow("g-audit-1");
    await excuseNoShow("admin1", {
      orderId: "g-audit-1",
      reason: "Admin-approved exception",
      note: "Documented exceptional circumstance",
    });

    const audit = await auditLog("g-audit-1");
    assert.equal(audit.action, "NO_SHOW_EXCUSED");
    assert.equal(audit.adminId, "admin1");
    assert.equal(audit.orderId, "g-audit-1");
    assert.equal(audit.studentId, "student1");
    // The audit record stores the caller admin's cafe name (the per-cafe
    // identity used throughout the scoping rework), not the legacy order
    // cafeId field.
    assert.equal(audit.cafeId, "Cafe A");
    assert.equal(audit.reason, "Admin-approved exception");
    assert.equal(audit.note, "Documented exceptional circumstance");
    assert.ok(audit.timestamp, "timestamp recorded");

    // Audit logs are immutable through the rules: update/delete denied.
    const adminRulesDb = testEnv.authenticatedContext("admin1").firestore();
    await assert.rejects(
      adminRulesDb.collection("audit_logs").doc(`NO_SHOW_EXCUSED_g-audit-1`)
        .update({ reason: "forged" }),
      (err) => err.code === "permission-denied" || err.code === 7,
    );
    await assert.rejects(
      adminRulesDb.collection("audit_logs").doc(`NO_SHOW_EXCUSED_g-audit-1`)
        .delete(),
      (err) => err.code === "permission-denied" || err.code === 7,
    );
  });

  it("Test 14 — concurrent excuses: only one succeeds", async () => {
    await fireNoShow("g-race-1");
    const results = await Promise.allSettled([
      excuseNoShow("admin1", {
        orderId: "g-race-1",
        reason: "Other",
        note: "test note",
      }),
      excuseNoShow("admin1", {
        orderId: "g-race-1",
        reason: "Other",
        note: "test note",
      }),
    ]);

    const fulfilled = results.filter((r) => r.status === "fulfilled");
    const rejected = results.filter((r) => r.status === "rejected");
    assert.equal(fulfilled.length, 1, "exactly one intervention succeeds");
    assert.equal(rejected.length, 1, "the loser is rejected");
    const loser = rejected[0].reason;
    assert.equal(loser.code, "failed-precondition");
    assert.match(loser.message, /already been excused/i);

    // Exactly one audit record and one notification.
    assert.equal(await countNotifications("g-race-1"), 1);
    assert.equal((await auditLog("g-race-1")).action, "NO_SHOW_EXCUSED");
  });
});

describe("Phase G — request validation & rules protection", () => {
  it("rejects an invalid reason", async () => {
    await fireNoShow("g-reason-1");
    await assert.rejects(
      excuseNoShow("admin1", {
        orderId: "g-reason-1",
        reason: "Arbitrary unapproved category",
      }),
      (err) => err.code === "invalid-argument",
    );
  });

  it("rejects an oversized note (> 200 chars)", async () => {
    await fireNoShow("g-note-1");
    await assert.rejects(
      excuseNoShow("admin1", {
        orderId: "g-note-1",
        reason: "Other",
        note: "x".repeat(201),
      }),
      (err) => err.code === "invalid-argument",
    );
  });

  it("rejects notes containing URLs or HTML", async () => {
    await fireNoShow("g-note-2");
    await assert.rejects(
      excuseNoShow("admin1", {
        orderId: "g-note-2",
        reason: "Other",
        note: "See https://evil.example",
      }),
      (err) => err.code === "invalid-argument",
    );
    await assert.rejects(
      excuseNoShow("admin1", {
        orderId: "g-note-2",
        reason: "Other",
        note: "<script>alert(1)</script>",
      }),
      (err) => err.code === "invalid-argument",
    );
  });

  it("rejects an unknown order", async () => {
    await assert.rejects(
      excuseNoShow("admin1", {
        orderId: "g-missing-1",
        reason: "Other",
        note: "test note",
      }),
      (err) => err.code === "not-found",
    );
  });

  it("rejects reason Other without a non-empty note", async () => {
    await fireNoShow("g-other-note-1");
    // No note at all.
    await assert.rejects(
      excuseNoShow("admin1", {
        orderId: "g-other-note-1",
        reason: "Other",
      }),
      (err) => {
        assert.equal(err.code, "invalid-argument");
        assert.match(err.message, /note is required/i);
        return true;
      },
    );
    const untouched = await orderById("g-other-note-1");
    assert.equal(untouched.noShowExcused, undefined, "nothing was written");

    // Whitespace-only note is still empty after trimming.
    await assert.rejects(
      excuseNoShow("admin1", {
        orderId: "g-other-note-1",
        reason: "Other",
        note: "   ",
      }),
      (err) => err.code === "invalid-argument",
    );
    const stillUntouched = await orderById("g-other-note-1");
    assert.equal(stillUntouched.noShowExcused, undefined);
  });

  it("students cannot forge noShowExcused on their own order (rules)", async () => {
    await fireNoShow("g-forge-1");
    const studentRulesDb = testEnv.authenticatedContext("student1", {
      email_verified: true,
    }).firestore();
    await assert.rejects(
      studentRulesDb.collection("orders").doc("g-forge-1").update({
        noShowExcused: true,
      }),
      (err) => err.code === "permission-denied" || err.code === 7,
    );
  });

  it("admins cannot write excuse fields directly (rules — callable only)", async () => {
    await fireNoShow("g-forge-2");
    const adminRulesDb = testEnv.authenticatedContext("admin1").firestore();
    await assert.rejects(
      adminRulesDb.collection("orders").doc("g-forge-2").update({
        noShowExcused: true,
        excusedBy: "admin1",
      }),
      (err) => err.code === "permission-denied" || err.code === 7,
    );
  });
});

describe("Phase G — deferred reliability correction when users/{studentId} is absent", () => {
  it("excusing a counted no-show with a missing user doc commits a reconciliation marker, never a silent skip", async () => {
    // Remove the student's user document so the inline correction cannot run.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc("student1").delete();
    });
    // Counted NO_SHOW (the engine wrote reliabilityProcessed + outcome).
    await seedOrder("g-deferred-1", validOrderPayload({
      status: "no_show",
      reliabilityProcessed: true,
      reliabilityOutcome: "NO_SHOW",
      noShowAt: new Date(),
    }));

    const result = await excuseNoShow("admin1", {
      orderId: "g-deferred-1",
      reason: "Student reported emergency",
    });
    assert.equal(result.success, true, "excuse still succeeds");

    // The excuse committed WITH a guaranteed-correction marker.
    const order = await orderById("g-deferred-1");
    assert.equal(order.noShowExcused, true);
    assert.equal(order.reliabilityExcusePending, true,
      "correction marker persisted, not silently skipped");
    assert.ok(
      order.reliabilityExcusePendingSince instanceof admin.firestore.Timestamp,
      "marker timestamp recorded");
    assert.equal(await userReliability(), undefined,
      "no summary exists while the user doc is absent");

    // Audit + notification still commit atomically with the excuse.
    assert.equal((await auditLog("g-deferred-1")).action, "NO_SHOW_EXCUSED");
    assert.equal(await countNotifications("g-deferred-1"), 1);
  });

  it("the scheduled processor applies the deferred correction once the user doc appears", async () => {
    // Same starting state as the previous test: counted NO_SHOW, no user doc.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc("student1").delete();
    });
    await seedOrder("g-deferred-2", validOrderPayload({
      status: "no_show",
      reliabilityProcessed: true,
      reliabilityOutcome: "NO_SHOW",
      noShowAt: new Date(),
    }));
    await excuseNoShow("admin1", {
      orderId: "g-deferred-2",
      reason: "System/application issue",
    });
    let order = await orderById("g-deferred-2");
    assert.equal(order.reliabilityExcusePending, true);

    // The user document is restored WITH the pre-excuse summary that still
    // counts the excused no-show.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const ref = ctx.firestore().collection("users").doc("student1");
      await ref.set({
        fullName: "Test Student",
        email: "student1@test.com",
        role: "student",
        accountStatus: "ACTIVE",
        createdAt: new Date(),
        pickupReliability: {
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
          recentPickupHistory: [
            { orderId: "g-deferred-2", outcome: "NO_SHOW", timestamp: new Date() },
            { orderId: "g-other-1", outcome: "COLLECTED", timestamp: new Date() },
            { orderId: "g-other-2", outcome: "COLLECTED", timestamp: new Date() },
          ],
        },
      });
    });

    // The scheduled processor reconciles the deferred correction.
    await functionsModule.processExpiredPickups.run({});

    order = await orderById("g-deferred-2");
    assert.equal(order.reliabilityExcusePending, undefined,
      "marker cleared after reconciliation");
    assert.equal(order.reliabilityExcuseSkippedReason, undefined,
      "no skip recorded — the correction was applied");
    const s = await userReliability();
    assert.equal(s.eligibleOrders, 2, "eligible decremented by reconcile");
    assert.equal(s.noShowOrders, 0, "no-show excluded by reconcile");
    assert.equal(s.collectedOrders, 2, "collected unchanged");
    assert.equal(s.recentEligibleOrders, 2);
    assert.equal(s.recentNoShowOrders, 0);
    assert.ok(
      !s.recentPickupHistory.some((e) => e.orderId === "g-deferred-2"),
      "excused order removed from recent history by reconcile");
  });

  it("the deferred correction gives up explicitly when the user doc never returns", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc("student1").delete();
    });
    const oldSince = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000);
    // Simulate an excuse committed long ago whose marker is still pending
    // (user doc never restored).
    await seedOrder("g-giveup-1", validOrderPayload({
      status: "no_show",
      reliabilityProcessed: true,
      reliabilityOutcome: "NO_SHOW",
      noShowAt: oldSince,
      noShowExcused: true,
      excusedAt: oldSince,
      excusedBy: "admin1",
      excuseReason: "Student reported emergency",
      excuseNote: null,
      reliabilityExcusePending: true,
      reliabilityExcusePendingSince: oldSince,
    }));

    await functionsModule.processExpiredPickups.run({});

    const order = await orderById("g-giveup-1");
    assert.equal(order.reliabilityExcusePending, undefined,
      "marker cleared after the retry window");
    assert.equal(order.reliabilityExcuseSkippedReason, "MISSING_USER",
      "explicit, auditable give-up recorded");
    assert.ok(
      order.reliabilityExcuseSkippedAt instanceof admin.firestore.Timestamp,
      "give-up timestamp recorded");
    assert.equal(await userReliability(), undefined,
      "no summary written for a never-restored user");
  });
});
