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

// Phase H — CAFE FOOD WASTE MANAGEMENT (setFoodDisposition): executable
// emulator coverage.
//
// This suite runs the REAL Firestore emulator with the REAL firestore.rules
// loaded and exercises the REAL exported `setFoodDisposition` callable
// against the emulator-backed Admin SDK, complementing the static guardrails
// in the Flutter foundation tests.
//
// It covers AGENTS.md Phase H section 41, Tests 1-13:
//   1  No-show eligibility           2  Collected order not eligible
//   3  Cancelled order not eligible  4  Record donated (order stays NO_SHOW)
//   5  Record disposed               6  Record resold
//   7  Duplicate disposition         8  Change disposition (DONATED→DISPOSED)
//   9  Unauthorized student         10  Unauthorized cafe admin
//  11  Concurrent admin actions     12  Reliability isolation
//  13  Order status isolation
//
// Plus the default-UNRESOLVED state on both no-show paths (scheduled and
// trigger), the protected-field rules (student + admin direct writes denied),
// note validation, and cafe-scoped audit read isolation.
//
// Run (requires Java 21+ — e.g. JAVA_HOME=/usr/lib/jvm/java-25-openjdk):
//   npm run test:disposition:integration   (inside functions/)

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
    await seed.collection("users").doc("admin3").set({
      fullName: "Admin Three",
      email: "admin3@test.com",
      role: "admin",
      cafeName: "Cafe A",
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
    await seed.collection("users").doc("noCafeAdmin").set({
      fullName: "No-Cafe Admin",
      email: "nocafe@test.com",
      role: "admin",
      cafeName: "",
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

async function seedReliability(uid, summary) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("users").doc(uid).update({
      pickupReliability: summary,
    });
  });
}

/** Seed a ready order whose pickup deadline has already expired so the
 *  scheduled processor flips it to no_show (and defaults the disposition). */
async function seedExpiredReadyOrder(orderId) {
  const past = new Date(Date.now() - 30 * 60000);
  await seedOrder(orderId, validOrderPayload({
    status: "ready",
    deadlineStatus: "ACTIVE",
    pickupDeadline: past,
  }));
}

function callableRequest(uid, data, token = { email_verified: true }) {
  return { auth: { uid, token }, data };
}

function setFoodDisposition(uid, data) {
  return functionsModule.setFoodDisposition.run(callableRequest(uid, data));
}

async function orderById(orderId) {
  const snap = await db.collection("orders").doc(orderId).get();
  return snap.exists ? snap.data() : null;
}

async function userReliability(uid = "student1") {
  const snap = await db.collection("users").doc(uid).get();
  return snap.exists ? snap.data().pickupReliability : undefined;
}

/** All FOOD_DISPOSITION audit records for an order, oldest first. */
async function dispositionAudits(orderId) {
  const snaps = await db
    .collection("audit_logs")
    .where("action", "==", "FOOD_DISPOSITION")
    .where("orderId", "==", orderId)
    .orderBy("timestamp", "asc")
    .get();
  return snaps.docs.map((d) => d.data());
}

function adminDb(uid = "admin1") {
  return testEnv.authenticatedContext(uid, { email_verified: true }).firestore();
}

function studentDb(uid = "student1") {
  return testEnv.authenticatedContext(uid, { email_verified: true }).firestore();
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

describe("Phase H — eligibility & authorization (Tests 1-3, 9-10)", () => {
  it("Test 1 — a NO_SHOW order can receive a food disposition", async () => {
    await seedOrder("fd-valid-1", validOrderPayload({ status: "no_show" }));
    const result = await setFoodDisposition("admin1", {
      orderId: "fd-valid-1",
      disposition: "DONATED",
      note: "Donated to campus support staff.",
    });
    assert.equal(result.success, true);
    assert.equal(result.alreadyRecorded, false);

    const order = await orderById("fd-valid-1");
    assert.equal(order.status, "no_show", "order stays NO_SHOW");
    assert.equal(order.foodDisposition, "DONATED");
    assert.ok(order.foodDispositionAt, "dispositionAt recorded");
    assert.equal(order.foodDispositionBy, "admin1");
    assert.equal(
      order.foodDispositionNote,
      "Donated to campus support staff.",
    );

    const audits = await dispositionAudits("fd-valid-1");
    assert.equal(audits.length, 1);
    assert.equal(audits[0].action, "FOOD_DISPOSITION");
    assert.equal(audits[0].previousDisposition, "UNRESOLVED");
    assert.equal(audits[0].newDisposition, "DONATED");
    assert.equal(audits[0].orderId, "fd-valid-1");
    assert.equal(audits[0].studentId, "student1");
    assert.equal(audits[0].cafeId, "Cafe A");
    assert.equal(audits[0].adminId, "admin1");
    assert.equal(audits[0].note, "Donated to campus support staff.");
  });

  it("Test 2 — a COLLECTED order cannot receive a disposition", async () => {
    await seedOrder("fd-collected-1", validOrderPayload({ status: "collected" }));
    await assert.rejects(
      setFoodDisposition("admin1", {
        orderId: "fd-collected-1",
        disposition: "DONATED",
      }),
      (err) => {
        assert.equal(err.code, "failed-precondition");
        assert.match(err.message, /Only no-show orders/);
        return true;
      },
    );
    const order = await orderById("fd-collected-1");
    assert.equal(order.foodDisposition, undefined, "nothing was written");
  });

  it("Test 3 — a CANCELLED order cannot receive a disposition", async () => {
    await seedOrder("fd-cancelled-1", validOrderPayload({ status: "cancelled" }));
    await assert.rejects(
      setFoodDisposition("admin1", {
        orderId: "fd-cancelled-1",
        disposition: "DONATED",
      }),
      (err) => err.code === "failed-precondition",
    );
  });

  it("a READY order cannot receive a disposition", async () => {
    await seedOrder("fd-ready-1", validOrderPayload({ status: "ready" }));
    await assert.rejects(
      setFoodDisposition("admin1", {
        orderId: "fd-ready-1",
        disposition: "DONATED",
      }),
      (err) => err.code === "failed-precondition",
    );
  });

  it("Test 9 — a student cannot record a disposition", async () => {
    await seedOrder("fd-student-1", validOrderPayload({ status: "no_show" }));
    await assert.rejects(
      setFoodDisposition("student1", {
        orderId: "fd-student-1",
        disposition: "DONATED",
      }),
      (err) => err.code === "permission-denied",
    );
  });

  it("Test 10 — a Cafe B admin cannot record a disposition on a Cafe A order",
    async () => {
      await seedOrder("fd-xcafe-1", validOrderPayload({ status: "no_show" }));
      await assert.rejects(
        setFoodDisposition("admin2", {
          orderId: "fd-xcafe-1",
          disposition: "DONATED",
        }),
        (err) => {
          assert.equal(err.code, "permission-denied");
          assert.match(err.message, /not authorized to manage orders/i);
          return true;
        },
      );
      const order = await orderById("fd-xcafe-1");
      assert.equal(order.foodDisposition, undefined, "nothing was written");
    });

  it("a suspended admin cannot record a disposition", async () => {
    await seedOrder("fd-susp-1", validOrderPayload({ status: "no_show" }));
    await assert.rejects(
      setFoodDisposition("suspendedAdmin", {
        orderId: "fd-susp-1",
        disposition: "DONATED",
      }),
      (err) => err.code === "permission-denied",
    );
    const order = await orderById("fd-susp-1");
    assert.equal(order.foodDisposition, undefined, "nothing was written");
  });

  it("an admin suspended before the disposition write is denied "
      + "(caller re-read inside the transaction)", async () => {
    await seedOrder("fd-race-susp-1", validOrderPayload({ status: "no_show" }));

    // Deterministic ordering: complete the suspension BEFORE invoking the
    // callable. The in-transaction caller re-read must observe the suspended
    // account and deny unconditionally — no write may commit from a stale
    // pre-suspension authorization snapshot.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc("admin1").update({
        accountStatus: "SUSPENDED",
      });
    });

    await assert.rejects(
      setFoodDisposition("admin1", {
        orderId: "fd-race-susp-1",
        disposition: "DONATED",
      }),
      (err) => err.code === "permission-denied",
    );
    const order = await orderById("fd-race-susp-1");
    assert.equal(
      order.foodDisposition,
      undefined,
      "suspension completed first — nothing recorded",
    );
  });

  it("an admin reassigned before the disposition write is denied for the "
      + "previous cafe scope", async () => {
    await seedOrder("fd-race-cafe-1", validOrderPayload({ status: "no_show" }));

    // Deterministic ordering: complete the reassignment BEFORE invoking the
    // callable. The in-transaction caller re-read must observe the new
    // cafeName and deny unconditionally — no write may commit under the
    // stale Cafe A scope.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc("admin1").update({
        cafeName: "Cafe B",
      });
    });

    await assert.rejects(
      setFoodDisposition("admin1", {
        orderId: "fd-race-cafe-1",
        disposition: "DONATED",
      }),
      (err) => err.code === "permission-denied",
    );
    const order = await orderById("fd-race-cafe-1");
    assert.equal(
      order.foodDisposition,
      undefined,
      "reassignment completed first — nothing recorded",
    );
  });

  it("an unknown order returns not-found", async () => {
    await assert.rejects(
      setFoodDisposition("admin1", {
        orderId: "fd-missing-1",
        disposition: "DONATED",
      }),
      (err) => err.code === "not-found",
    );
  });

  it("an invalid disposition value is rejected", async () => {
    await seedOrder("fd-badval-1", validOrderPayload({ status: "no_show" }));
    await assert.rejects(
      setFoodDisposition("admin1", {
        orderId: "fd-badval-1",
        disposition: "SOME_FREE_FORM_VALUE",
      }),
      (err) => err.code === "invalid-argument",
    );
  });

  it("UNRESOLVED is never an admin-chosen target", async () => {
    await seedOrder("fd-unres-1", validOrderPayload({ status: "no_show" }));
    await assert.rejects(
      setFoodDisposition("admin1", {
        orderId: "fd-unres-1",
        disposition: "UNRESOLVED",
      }),
      (err) => err.code === "invalid-argument",
    );
  });

  it("note validation — too long, HTML, and URLs are rejected", async () => {
    await seedOrder("fd-note-1", validOrderPayload({ status: "no_show" }));
    await assert.rejects(
      setFoodDisposition("admin1", {
        orderId: "fd-note-1",
        disposition: "DONATED",
        note: "x".repeat(201),
      }),
      (err) => err.code === "invalid-argument",
    );
    await assert.rejects(
      setFoodDisposition("admin1", {
        orderId: "fd-note-1",
        disposition: "DONATED",
        note: "<script>alert(1)</script>",
      }),
      (err) => err.code === "invalid-argument",
    );
    await assert.rejects(
      setFoodDisposition("admin1", {
        orderId: "fd-note-1",
        disposition: "DONATED",
        note: "https://evil.example.com",
      }),
      (err) => err.code === "invalid-argument",
    );
    const order = await orderById("fd-note-1");
    assert.equal(order.foodDisposition, undefined, "nothing was written");
  });
});

describe("Phase H — recorded outcomes keep NO_SHOW (Tests 4-6, 13)", () => {
  it("Test 4 — recording DONATED keeps the order NO_SHOW", async () => {
    await seedOrder("fd-donated-1", validOrderPayload({ status: "no_show" }));
    await setFoodDisposition("admin1", {
      orderId: "fd-donated-1",
      disposition: "DONATED",
    });
    const order = await orderById("fd-donated-1");
    assert.equal(order.status, "no_show", "order remains NO_SHOW");
    assert.equal(order.foodDisposition, "DONATED");
  });

  it("Test 5 — recording DISPOSED keeps the order NO_SHOW", async () => {
    await seedOrder("fd-disposed-1", validOrderPayload({ status: "no_show" }));
    await setFoodDisposition("admin1", {
      orderId: "fd-disposed-1",
      disposition: "DISPOSED",
      note: "Food no longer suitable for service.",
    });
    const order = await orderById("fd-disposed-1");
    assert.equal(order.status, "no_show", "order remains NO_SHOW");
    assert.equal(order.foodDisposition, "DISPOSED");
    assert.equal(order.foodDispositionNote, "Food no longer suitable for service.");
  });

  it("Test 6 — recording RESOLD keeps the order NO_SHOW", async () => {
    await seedOrder("fd-resold-1", validOrderPayload({ status: "no_show" }));
    await setFoodDisposition("admin1", {
      orderId: "fd-resold-1",
      disposition: "RESOLD",
    });
    const order = await orderById("fd-resold-1");
    assert.equal(order.status, "no_show", "order remains NO_SHOW");
    assert.equal(order.foodDisposition, "RESOLD");
    // No second order, no price change — operational record only (§31).
    // Assert the entire food_items collection is empty (the suite never
    // seeds food items), not just the food_1 document, so a bug that writes
    // a listing under any other ID is caught.
    const foods = await db.collection("food_items").get();
    assert.equal(foods.size, 0, "no food listing was created");
  });

  it("Test 13 — every other disposition keeps the order NO_SHOW", async () => {
    for (const d of ["DISCOUNTED", "STAFF_USE", "OTHER"]) {
      await seedOrder(`fd-iso-${d}`, validOrderPayload({ status: "no_show" }));
      await setFoodDisposition("admin1", {
        orderId: `fd-iso-${d}`,
        disposition: d,
      });
      const order = await orderById(`fd-iso-${d}`);
      assert.equal(order.status, "no_show", `${d} keeps NO_SHOW`);
      assert.equal(order.foodDisposition, d);
    }
  });
});

describe("Phase H — idempotency & corrections (Tests 7-8)", () => {
  it("Test 7 — a duplicate disposition writes nothing and adds no audit",
    async () => {
      await seedOrder("fd-dup-1", validOrderPayload({
        status: "no_show",
        foodDisposition: "DONATED",
        foodDispositionAt: new Date(),
        foodDispositionBy: "admin1",
      }));
      const result = await setFoodDisposition("admin1", {
        orderId: "fd-dup-1",
        disposition: "DONATED",
        note: "Already donated earlier.",
      });
      assert.equal(result.success, true);
      assert.equal(result.alreadyRecorded, true, "idempotent duplicate");

      const order = await orderById("fd-dup-1");
      assert.equal(order.foodDisposition, "DONATED");
      assert.equal(
        order.foodDispositionNote,
        undefined,
        "existing note not overwritten by duplicate",
      );
      const audits = await dispositionAudits("fd-dup-1");
      assert.equal(audits.length, 0, "no duplicate audit record");
    });

  it("Test 8 — changing DONATED → DISPOSED updates the order and audits both",
    async () => {
      await seedOrder("fd-change-1", validOrderPayload({ status: "no_show" }));
      await setFoodDisposition("admin1", {
        orderId: "fd-change-1",
        disposition: "DONATED",
        note: "Donated to support staff.",
      });
      const result = await setFoodDisposition("admin1", {
        orderId: "fd-change-1",
        disposition: "DISPOSED",
        note: "Later found unsafe.",
      });
      assert.equal(result.alreadyRecorded, false);

      const order = await orderById("fd-change-1");
      assert.equal(order.status, "no_show", "still NO_SHOW");
      assert.equal(order.foodDisposition, "DISPOSED", "current reflects latest");
      assert.equal(order.foodDispositionNote, "Later found unsafe.");

      const audits = await dispositionAudits("fd-change-1");
      assert.equal(audits.length, 2, "both changes audited");
      assert.equal(audits[0].previousDisposition, "UNRESOLVED");
      assert.equal(audits[0].newDisposition, "DONATED");
      assert.equal(audits[1].previousDisposition, "DONATED");
      assert.equal(audits[1].newDisposition, "DISPOSED");
    });

  it("changing the disposition without a new note clears the stale note",
    async () => {
      await seedOrder("fd-note-clear-1", validOrderPayload({ status: "no_show" }));
      await setFoodDisposition("admin1", {
        orderId: "fd-note-clear-1",
        disposition: "DONATED",
        note: "Donated to support staff.",
      });
      // Change to DISPOSED WITHOUT a note: the order must not keep the
      // donation note (it would contradict "Disposed"). The prior note
      // remains only in the immutable audit trail.
      const result = await setFoodDisposition("admin1", {
        orderId: "fd-note-clear-1",
        disposition: "DISPOSED",
      });
      assert.equal(result.alreadyRecorded, false);

      const order = await orderById("fd-note-clear-1");
      assert.equal(order.foodDisposition, "DISPOSED");
      assert.equal(
        order.foodDispositionNote,
        undefined,
        "stale note cleared on disposition change",
      );

      const audits = await dispositionAudits("fd-note-clear-1");
      assert.equal(audits.length, 2);
      assert.equal(audits[0].newDisposition, "DONATED");
      assert.equal(audits[0].note, "Donated to support staff.");
      assert.equal(audits[1].newDisposition, "DISPOSED");
      assert.equal(audits[1].note, null);
    });

  it("Test 11 — concurrent identical admin actions commit exactly once",
    async () => {
      await seedOrder("fd-race-1", validOrderPayload({ status: "no_show" }));
      const results = await Promise.allSettled([
        setFoodDisposition("admin1", {
          orderId: "fd-race-1",
          disposition: "DONATED",
        }),
        setFoodDisposition("admin3", {
          orderId: "fd-race-1",
          disposition: "DONATED",
        }),
      ]);
      assert.equal(results[0].status, "fulfilled");
      assert.equal(results[1].status, "fulfilled");

      const order = await orderById("fd-race-1");
      assert.equal(order.foodDisposition, "DONATED");

      // The transaction serializes both attempts: the loser re-reads the
      // committed disposition and returns alreadyRecorded without writing —
      // exactly one audit record, never two.
      const audits = await dispositionAudits("fd-race-1");
      assert.equal(audits.length, 1, "exactly one audit record");
    });

  it("Test 11b — concurrent different admin actions end in one consistent "
      + "state, both changes audited", async () => {
    await seedOrder("fd-race-2", validOrderPayload({ status: "no_show" }));
    const results = await Promise.allSettled([
      setFoodDisposition("admin1", {
        orderId: "fd-race-2",
        disposition: "DONATED",
      }),
      setFoodDisposition("admin3", {
        orderId: "fd-race-2",
        disposition: "RESOLD",
      }),
    ]);
    assert.equal(results[0].status, "fulfilled");
    assert.equal(results[1].status, "fulfilled");

    const order = await orderById("fd-race-2");
    assert.equal(
      order.foodDisposition === "DONATED" ||
        order.foodDisposition === "RESOLD",
      true,
      "final state is exactly one recorded disposition",
    );

    const audits = await dispositionAudits("fd-race-2");
    assert.equal(audits.length, 2, "both distinct changes audited");
    assert.notEqual(
      audits[0].newDisposition,
      audits[1].newDisposition,
      "the two recorded outcomes differ",
    );
  });
});

describe("Phase H — reliability isolation (Test 12)", () => {
  it("changing a food disposition leaves the reliability summary unchanged",
    async () => {
      // Timestamps are normalized to ISO strings so the seeded (client-SDK
      // Date) and read-back (Admin-SDK Timestamp) representations compare
      // equal — the values are identical, only the SDK wrappers differ.
      const normalize = (s) => JSON.parse(JSON.stringify(s, (key, value) => {
        if (value instanceof Date) return value.toISOString();
        if (value && typeof value === "object" &&
            typeof value.toDate === "function") {
          return value.toDate().toISOString();
        }
        return value;
      }));
      const summary = {
        eligibleOrders: 10,
        collectedOrders: 7,
        noShowOrders: 3,
        collectionRate: 70,
        recentEligibleOrders: 5,
        recentCollectedOrders: 3,
        recentNoShowOrders: 2,
        recentCollectionRate: 60,
        reliabilityScore: 64.7,
        status: "NEEDS_IMPROVEMENT",
        restrictionLevel: "NORMAL",
        restrictionReason: null,
        recentPickupHistory: [
          { orderId: "h1", outcome: "NO_SHOW", timestamp: new Date() },
        ],
      };
      await seedReliability("student1", summary);
      await seedOrder("fd-rel-1", validOrderPayload({
        status: "no_show",
        reliabilityProcessed: true,
        reliabilityOutcome: "NO_SHOW",
        noShowAt: new Date(),
        expiredAt: new Date(),
      }));

      await setFoodDisposition("admin1", {
        orderId: "fd-rel-1",
        disposition: "DONATED",
      });

      const after = await userReliability();
      assert.deepEqual(
        normalize(after),
        normalize(summary),
        "reliability summary completely unchanged by disposition",
      );
    });
});

describe("Phase H — default UNRESOLVED state (AGENTS.md §3)", () => {
  it("the scheduled no-show processor defaults the disposition to UNRESOLVED",
    async () => {
      await seedExpiredReadyOrder("fd-sched-1");
      await functionsModule.processExpiredPickups.run({});
      const order = await orderById("fd-sched-1");
      assert.equal(order.status, "no_show");
      assert.equal(order.foodDisposition, "UNRESOLVED");
    });

  it("the manual no-show trigger defaults the disposition to UNRESOLVED "
      + "when absent", async () => {
    await seedOrder("fd-trig-1", validOrderPayload({ status: "ready" }));
    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "fd-trig-1",
      validOrderPayload({ status: "ready" }),
      validOrderPayload({ status: "no_show" }),
    ));
    const order = await orderById("fd-trig-1");
    assert.equal(order.status, "no_show");
    assert.equal(order.foodDisposition, "UNRESOLVED");
  });

  it("an already-recorded disposition is not overwritten by a no-show "
      + "bookkeeping event", async () => {
    // Order is already NO_SHOW with a recorded disposition; a redelivered or
    // duplicate no-show trigger must not reset it to UNRESOLVED.
    await seedOrder("fd-trig-keep-1", validOrderPayload({
      status: "no_show",
      expiredAt: new Date(),
      foodDisposition: "DONATED",
    }));
    await functionsModule.onOrderStatusChanged.run(await makeStatusChangeEvent(
      "fd-trig-keep-1",
      validOrderPayload({ status: "ready" }),
      validOrderPayload({
        status: "no_show",
        expiredAt: new Date(),
        foodDisposition: "DONATED",
      }),
    ));
    const order = await orderById("fd-trig-keep-1");
    assert.equal(order.foodDisposition, "DONATED", "disposition preserved");
  });
});

describe("Phase H — Firestore rules (AGENTS.md §38)", () => {
  it("denies a student direct write of foodDisposition fields", async () => {
    await seedOrder("fd-rule-student-1", validOrderPayload({ status: "no_show" }));
    await assert.rejects(
      studentDb().collection("orders").doc("fd-rule-student-1").update({
        foodDisposition: "DONATED",
        updatedAt: new Date(),
      }),
      (err) => err.code === "permission-denied",
    );
  });

  it("denies an admin direct write of foodDisposition fields — only the "
      + "callable may write them", async () => {
    await seedOrder("fd-rule-admin-1", validOrderPayload({ status: "no_show" }));
    await assert.rejects(
      adminDb("admin1").collection("orders").doc("fd-rule-admin-1").update({
        foodDisposition: "DONATED",
        updatedAt: new Date(),
      }),
      (err) => err.code === "permission-denied",
    );
  });

  it("audit records are readable only by an admin of the same cafe",
    async () => {
      await seedOrder("fd-audit-1", validOrderPayload({ status: "no_show" }));
      await setFoodDisposition("admin1", {
        orderId: "fd-audit-1",
        disposition: "DONATED",
      });
      const auditSnaps = await db
        .collection("audit_logs")
        .where("action", "==", "FOOD_DISPOSITION")
        .where("orderId", "==", "fd-audit-1")
        .get();
      assert.equal(auditSnaps.size, 1);
      const auditId = auditSnaps.docs[0].id;

      // Cafe A admin (the acting admin's cafe) may read the record.
      const ownSnap = await adminDb("admin1")
        .collection("audit_logs")
        .doc(auditId)
        .get();
      assert.equal(ownSnap.exists, true);

      // Cafe B admin is denied the cross-cafe audit record.
      await assert.rejects(
        adminDb("admin2").collection("audit_logs").doc(auditId).get(),
        (err) => err.code === "permission-denied",
      );

      // Audit records are append-only — no client update or delete.
      await assert.rejects(
        adminDb("admin1").collection("audit_logs").doc(auditId).update({
          note: "tampered",
        }),
        (err) => err.code === "permission-denied",
      );
      await assert.rejects(
        adminDb("admin1").collection("audit_logs").doc(auditId).delete(),
        (err) => err.code === "permission-denied",
      );
    });

  it("a cafeless-order audit record stays readable by any active admin",
    async () => {
      // A genuinely cafeless (UNASSIGNED) order served by an admin whose
      // profile has NO cafeName: the audit record's cafeId is an empty
      // string, which adminCanReadAudit() treats as any-admin readable.
      // (cafeId must never be null — a null value would make the read
      // rule's size() evaluation fail closed for every admin.)
      await seedOrder("fd-audit-cafe-1", validOrderPayload({
        status: "no_show",
        cafes: ["UNASSIGNED"],
      }));
      await setFoodDisposition("noCafeAdmin", {
        orderId: "fd-audit-cafe-1",
        disposition: "DONATED",
      });
      const auditSnaps = await db
        .collection("audit_logs")
        .where("action", "==", "FOOD_DISPOSITION")
        .where("orderId", "==", "fd-audit-cafe-1")
        .get();
      assert.equal(auditSnaps.size, 1);
      const auditId = auditSnaps.docs[0].id;
      const cafeId = auditSnaps.docs[0].data().cafeId;
      assert.equal(cafeId, "", "empty cafeId for a cafeless acting admin");

      // Any active admin may read the record (empty cafeId → any-admin).
      const ownSnap = await adminDb("admin1")
        .collection("audit_logs")
        .doc(auditId)
        .get();
      assert.equal(ownSnap.exists, true);
      const crossSnap = await adminDb("admin2")
        .collection("audit_logs")
        .doc(auditId)
        .get();
      assert.equal(crossSnap.exists, true);
    });
});
