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

// PHASE 18 — PER-CAFE ADMIN SCOPING: executable emulator/integration coverage.
//
// This suite runs the REAL Firestore emulator with the REAL firestore.rules
// loaded and verifies that admin order read/update/delete access is scoped to
// the admin's own cafe via the server-authoritative `cafes` array
// (adminServesOrder()), complementing the static guardrails in
// test/auth_hardening_test.dart and the foundation suites.
//
// It covers:
//   1  Admin reads an order from their own cafe
//   2  Admin is denied reading an order from another cafe
//   3  Admin updates an order from their own cafe (status transition)
//   4  Admin is denied updating an order from another cafe
//   5  Admin is denied deleting an order from another cafe
//   6  Legacy orders (no `cafes`) are not admin-readable until backfilled
//   7  An admin without a cafeName cannot read scoped orders
//   8  Students cannot forge the `cafes` array (no create rule; protected on update)
//   9  placeOrder writes the server-authoritative `cafes` array
//
// Run (requires Java 21+ — e.g. JAVA_HOME=/usr/lib/jvm/java-25-openjdk):
//   npm run test:cafe-scoping:integration   (inside functions/)

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
    // Server-authoritative per-cafe scoping list (written by placeOrder /
    // the backfill helpers; protected from client writes by the rules).
    cafes: ["Cafe A"],
    ...overrides,
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
      createdAt: new Date(),
    });
    await seed.collection("users").doc("adminA").set({
      fullName: "Admin A",
      email: "admina@test.com",
      role: "admin",
      accountStatus: "ACTIVE",
      cafeName: "Cafe A",
      createdAt: new Date(),
    });
    await seed.collection("users").doc("adminB").set({
      fullName: "Admin B",
      email: "adminb@test.com",
      role: "admin",
      accountStatus: "ACTIVE",
      cafeName: "Cafe B",
      createdAt: new Date(),
    });
    // Admin with no cafe association yet (profile incomplete).
    await seed.collection("users").doc("adminNoCafe").set({
      fullName: "Admin NoCafe",
      email: "adminnc@test.com",
      role: "admin",
      accountStatus: "ACTIVE",
      createdAt: new Date(),
    });
  });
}

async function seedOrder(orderId, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("orders").doc(orderId).set(data);
  });
}

function adminDb(uid) {
  return testEnv.authenticatedContext(uid).firestore();
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

describe("per-cafe admin order access (adminServesOrder)", () => {
  it("Test 1 — an admin reads an order from their own cafe", async () => {
    await seedOrder("scope-own-1", validOrderPayload({ cafes: ["Cafe A"] }));
    const snap = await adminDb("adminA")
        .collection("orders")
        .doc("scope-own-1")
        .get();
    assert.equal(snap.exists, true);
    assert.equal(snap.data().status, "pending");
  });

  it("Test 2 — an admin is denied reading an order from another cafe", async () => {
    await seedOrder("scope-other-1", validOrderPayload({ cafes: ["Cafe B"] }));
    await assert.rejects(
      adminDb("adminA").collection("orders").doc("scope-other-1").get(),
      (err) => err.code === "permission-denied",
    );
    // And the scoped query the admin app runs only returns own-cafe orders.
    const own = await adminDb("adminA")
        .collection("orders")
        .where("cafes", "array-contains", "Cafe A")
        .get();
    assert.equal(own.size, 0);
  });

  it("Test 3 — an admin updates an order from their own cafe", async () => {
    await seedOrder("scope-upd-own-1", validOrderPayload({
      cafes: ["Cafe A"],
      status: "accepted",
      createdAt: new Date(Date.now() - 3 * 60000),
      cancellationDeadline: new Date(Date.now() - 1000),
    }));
    await adminDb("adminA")
        .collection("orders")
        .doc("scope-upd-own-1")
        .update({ status: "preparing", updatedAt: new Date() });
    const after = await db.collection("orders").doc("scope-upd-own-1").get();
    assert.equal(after.data().status, "preparing");
  });

  it("Test 4 — an admin is denied updating an order from another cafe", async () => {
    await seedOrder("scope-upd-other-1", validOrderPayload({
      cafes: ["Cafe B"],
      status: "accepted",
      createdAt: new Date(Date.now() - 3 * 60000),
      cancellationDeadline: new Date(Date.now() - 1000),
    }));
    await assert.rejects(
      adminDb("adminA")
          .collection("orders")
          .doc("scope-upd-other-1")
          .update({ status: "preparing", updatedAt: new Date() }),
      (err) => err.code === "permission-denied",
    );
    const after = await db.collection("orders").doc("scope-upd-other-1").get();
    assert.equal(after.data().status, "accepted");
  });

  it("Test 5 — an admin is denied deleting an order from another cafe", async () => {
    await seedOrder("scope-del-other-1", validOrderPayload({ cafes: ["Cafe B"] }));
    await assert.rejects(
      adminDb("adminA").collection("orders").doc("scope-del-other-1").delete(),
      (err) => err.code === "permission-denied",
    );
    const after = await db.collection("orders").doc("scope-del-other-1").get();
    assert.equal(after.exists, true);
  });

  it("Test 6 — legacy orders (no `cafes`) are not admin-readable until "
      + "backfilled (scoping never bypassed)", async () => {
    const legacy = validOrderPayload();
    delete legacy.cafes;
    await seedOrder("scope-legacy-1", legacy);
    // No admin — not even one with a matching cafe — can read a cafeless
    // order through the client rules; the absent-field fallback is gone.
    await assert.rejects(
      adminDb("adminA").collection("orders").doc("scope-legacy-1").get(),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      adminDb("adminB").collection("orders").doc("scope-legacy-1").get(),
      (err) => err.code === "permission-denied",
    );
    // Privileged backfill (Admin SDK) still works and restores normal
    // scoping: once tagged with Cafe A, adminA can operate and adminB is
    // denied.
    await db.collection("orders").doc("scope-legacy-1").update({
      cafes: ["Cafe A"],
      updatedAt: new Date(),
    });
    const backfilled = await adminDb("adminA")
        .collection("orders")
        .doc("scope-legacy-1")
        .get();
    assert.equal(backfilled.exists, true);
    await assert.rejects(
      adminDb("adminB").collection("orders").doc("scope-legacy-1").get(),
      (err) => err.code === "permission-denied",
    );
  });

  it("Test 7 — an admin without a cafeName cannot read scoped orders", async () => {
    await seedOrder("scope-nocafe-1", validOrderPayload({ cafes: ["Cafe A"] }));
    await assert.rejects(
      adminDb("adminNoCafe").collection("orders").doc("scope-nocafe-1").get(),
      (err) => err.code === "permission-denied",
    );
  });

  it("Test 8 — students cannot forge the `cafes` array", async () => {
    // No client create rule exists on /orders (placeOrder is the only
    // creator), so a direct student create with a forged cafes list is
    // rejected outright.
    await assert.rejects(
      testEnv.authenticatedContext("student1")
          .firestore()
          .collection("orders")
          .doc("scope-forge-create-1")
          .set(validOrderPayload({ cafes: ["Cafe B"] })),
      (err) => err.code === "permission-denied",
    );
    // And an admin cannot rewrite the cafes list on update (protected field).
    await seedOrder("scope-forge-upd-1", validOrderPayload({ cafes: ["Cafe A"] }));
    await assert.rejects(
      adminDb("adminA")
          .collection("orders")
          .doc("scope-forge-upd-1")
          .update({ cafes: ["Cafe B"], updatedAt: new Date() }),
      (err) => err.code === "permission-denied",
    );
  });

  it("Test 9 — placeOrder writes the server-authoritative `cafes` array",
      async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("food_items").doc("food_1").set({
        id: "food_1",
        title: "Rice & Beans",
        price: 3000,
        available: true,
        createdAt: new Date(),
        updatedAt: new Date(),
      });
    });
    await functionsModule.placeOrder.run({
      auth: { uid: "student1", token: { email_verified: true } },
      data: {
        orderId: "scope-place-1",
        studentId: "student1",
        userName: "Test Student",
        items: [{
          foodItemId: "food_1",
          title: "Rice & Beans",
          price: 3000,
          quantity: 1,
          image: "",
          selectedCafe: "Cafe A",
        }],
        foodIds: ["food_1"],
        price: 3000,
        cafeId: "cafe1",
        cafeLocation: null,
        distanceMeters: 200,
        distanceCalculated: false,
        pickupWindowMinutes: 20,
      },
    });
    const snap = await db.collection("orders").doc("scope-place-1").get();
    assert.deepEqual(snap.data().cafes, ["Cafe A"]);
    // The order is visible to Cafe A's admin and hidden from Cafe B's.
    const adminASnap = await adminDb("adminA")
        .collection("orders")
        .doc("scope-place-1")
        .get();
    assert.equal(adminASnap.exists, true);
    await assert.rejects(
      adminDb("adminB").collection("orders").doc("scope-place-1").get(),
      (err) => err.code === "permission-denied",
    );
  });

  it("Test 10 — cafeless orders omit the `cafes` field and are not "
      + "admin-readable until backfilled", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("food_items").doc("food_1").set({
        id: "food_1",
        title: "Rice & Beans",
        price: 3000,
        available: true,
        createdAt: new Date(),
        updatedAt: new Date(),
      });
    });
    // All-cafeless payload (e.g. off-campus items without a cafe selection).
    await functionsModule.placeOrder.run({
      auth: { uid: "student1", token: { email_verified: true } },
      data: {
        orderId: "scope-place-cafeless",
        studentId: "student1",
        userName: "Test Student",
        items: [{
          foodItemId: "food_1",
          title: "Rice & Beans",
          price: 3000,
          quantity: 1,
          image: "",
          selectedCafe: null,
        }],
        foodIds: ["food_1"],
        price: 3000,
        cafeId: null,
        cafeLocation: null,
        distanceMeters: null,
        distanceCalculated: false,
        pickupWindowMinutes: 20,
      },
    });
    // The `cafes` field is omitted entirely — never an empty array — so the
    // absent-field legacy fallback applies everywhere (rules, notifications,
    // migration).
    const snap = await db.collection("orders").doc("scope-place-cafeless").get();
    assert.equal(snap.exists, true);
    assert.equal(
      "cafes" in snap.data(),
      false,
      "cafeless order must omit the cafes field",
    );
    // No admin may read a cafeless order through the client rules — the
    // backend backfill (Admin SDK) must tag it before it becomes
    // accessible, so per-cafe scoping is never bypassed.
    await assert.rejects(
      adminDb("adminA").collection("orders").doc("scope-place-cafeless").get(),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      adminDb("adminB").collection("orders").doc("scope-place-cafeless").get(),
      (err) => err.code === "permission-denied",
    );
  });

  it("Test 11 — onNewOrder notifies only the scoped cafe admin for a legacy "
      + "order backfilled with cafes", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("food_items").doc("food_1").set({
        id: "food_1",
        title: "Rice & Beans",
        price: 3000,
        available: true,
        createdAt: new Date(),
        updatedAt: new Date(),
      });
    });

    // Legacy order: NO `cafes` field, items carrying Cafe A.
    const orderId = "scope-legacy-notif";
    const orderData = validOrderPayload({ orderId });
    delete orderData.cafes;
    await seedOrder(orderId, orderData);

    // Invoke the real onNewOrder trigger (document-created event shape).
    const ref = db.collection("orders").doc(orderId);
    const snapshot = { ref, data: () => orderData, exists: true };
    await functionsModule.onNewOrder.run({ data: snapshot, params: { orderId } });

    // The backfill tagged the legacy order with its derived cafe.
    const orderSnap = await db.collection("orders").doc(orderId).get();
    assert.deepEqual(orderSnap.data().cafes, ["Cafe A"]);

    // Only Cafe A's admin was notified — not Cafe B, not the no-cafe admin.
    const notifs = await db.collection("notifications").get();
    const recipientIds = notifs.docs
        .map((d) => d.data().recipientId);
    assert.deepEqual(
      [...new Set(recipientIds)],
      ["adminA"],
      "legacy order backfilled with Cafe A must notify only adminA",
    );
  });

  it("Test 12 — onNewOrder treats an EMPTY cafes array as absent and "
      + "derives the cafe from items for notifications", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("food_items").doc("food_1").set({
        id: "food_1",
        title: "Rice & Beans",
        price: 3000,
        available: true,
        createdAt: new Date(),
        updatedAt: new Date(),
      });
    });

    // Legacy order written by the old `cafes: deriveOrderCafes(...) || []`
    // behaviour: an EMPTY array. The backfill refuses to touch any existing
    // cafes value, so this order is permanently tagged `[]` — an empty array
    // must therefore be treated as absent for notification scoping, or the
    // order would notify zero admins (filter over an empty list).
    const orderId = "scope-empty-cafes-notif";
    const orderData = validOrderPayload({ orderId });
    orderData.cafes = [];
    await seedOrder(orderId, orderData);

    // Invoke the real onNewOrder trigger (document-created event shape).
    const ref = db.collection("orders").doc(orderId);
    const snapshot = { ref, data: () => orderData, exists: true };
    await functionsModule.onNewOrder.run({ data: snapshot, params: { orderId } });

    // The backfill aborted (empty array counts as an existing value), so the
    // stored cafes remain []; the notification must still be scoped via the
    // items-derived cafes rather than notifying zero admins.
    const orderSnap = await db.collection("orders").doc(orderId).get();
    assert.deepEqual(orderSnap.data().cafes, []);

    const notifs = await db.collection("notifications").get();
    const recipientIds = notifs.docs
        .map((d) => d.data().recipientId);
    assert.deepEqual(
      [...new Set(recipientIds)],
      ["adminA"],
      "order with an empty cafes array must notify its cafe admin (Cafe A)",
    );
  });
});

describe("cart serialization lock document (_cart_lock_)", () => {
  const ownerCart = () => testEnv
      .authenticatedContext("student1")
      .firestore()
      .collection("users")
      .doc("student1")
      .collection("cart");

  it("lets the owner write the lock payload {cafe, lockedAt}", async () => {
    await ownerCart().doc("_cart_lock_").set({
      cafe: "Cafe A",
      lockedAt: new Date(),
    });
    const snap = await db
        .collection("users").doc("student1").collection("cart")
        .doc("_cart_lock_").get();
    assert.equal(snap.exists, true);
  });

  it("rejects a lock write carrying item fields or extra fields", async () => {
    await assert.rejects(
      ownerCart().doc("_cart_lock_").set({
        cafe: "Cafe A",
        lockedAt: new Date(),
        foodItemId: "food_1",
        quantity: 1,
      }),
      (err) => err.code === "permission-denied",
    );
  });

  it("rejects a lock payload written to a normal cart item ID", async () => {
    await assert.rejects(
      ownerCart().doc("food_1_Cafe A").set({
        cafe: "Cafe A",
        lockedAt: new Date(),
      }),
      (err) => err.code === "permission-denied",
    );
  });

  it("rejects a malformed lock payload (wrong types)", async () => {
    await assert.rejects(
      ownerCart().doc("_cart_lock_").set({ cafe: 5, lockedAt: new Date() }),
      (err) => err.code === "permission-denied",
    );
  });

  it("lets the owner delete the lock; normal cart item writes still "
      + "validate as items", async () => {
    await ownerCart().doc("_cart_lock_").set({
      cafe: "Cafe A",
      lockedAt: new Date(),
    });
    await ownerCart().doc("_cart_lock_").delete();
    // A lock payload on a normal item ID is still rejected (item rule).
    await assert.rejects(
      ownerCart().doc("food_1_Cafe A").set({
        cafe: "Cafe A",
        lockedAt: new Date(),
      }),
      (err) => err.code === "permission-denied",
    );
    // And a genuine item write passes validCartItemWrite as before.
    await ownerCart().doc("food_1_Cafe A").set({
      foodItemId: "food_1",
      quantity: 1,
      selectedCafe: "Cafe A",
    });
    const snap = await db
        .collection("users").doc("student1").collection("cart")
        .doc("food_1_Cafe A").get();
    assert.equal(snap.exists, true);
  });
});

describe("createAdminAccount callable (no self-registration)", () => {
  // The auth emulator is not part of this suite's --only firestore boot, so
  // stub the Admin SDK auth user creation; the callable's authorization and
  // profile/audit writes are what we exercise here.
  const realCreateUser = admin.auth().createUser;

  after(() => {
    admin.auth().createUser = realCreateUser;
  });

  function invoke(uid, data) {
    return functionsModule.createAdminAccount.run({ auth: { uid }, data });
  }

  it("rejects a non-admin caller (no self-registration)", async () => {
    await assert.rejects(
      invoke("student1", {
        fullName: "New Admin",
        cafeName: "Cafe A",
        email: "newadmin@test.com",
        phoneNumber: "",
        password: "secret123",
      }),
      (err) => err.code === "permission-denied",
    );
  });

  it("rejects a suspended admin caller", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc("adminSuspended").set({
        fullName: "Suspended Admin",
        email: "suspended@test.com",
        role: "admin",
        accountStatus: "SUSPENDED",
        cafeName: "Cafe A",
        createdAt: new Date(),
      });
    });
    await assert.rejects(
      invoke("adminSuspended", {
        fullName: "New Admin",
        cafeName: "Cafe A",
        email: "newadmin2@test.com",
        phoneNumber: "",
        password: "secret123",
      }),
      (err) => err.code === "permission-denied",
    );
  });

  it("an existing admin creates a new admin (auth + profile + audit)", async () => {
    admin.auth().createUser = async (props) => ({
      uid: "created-admin-uid",
      email: props.email,
    });
    try {
      const result = await invoke("adminA", {
        fullName: "New Admin",
        cafeName: "Cafe A",
        email: "newadmin@test.com",
        phoneNumber: "0712 345 678",
        password: "secret123",
      });
      assert.equal(result.uid, "created-admin-uid");

      const profile = await db.collection("users").doc("created-admin-uid").get();
      assert.equal(profile.data().role, "admin");
      assert.equal(profile.data().accountStatus, "ACTIVE");
      assert.equal(profile.data().cafeName, "Cafe A");
      assert.equal(profile.data().fullName, "New Admin");
      assert.equal(profile.data().email, "newadmin@test.com");

      const audit = await db
          .collection("audit_logs")
          .where("action", "==", "CREATE_ADMIN")
          .get();
      assert.equal(audit.size, 1, "a CREATE_ADMIN audit record must be written");
      assert.equal(audit.docs[0].data().adminId, "adminA");
    } finally {
      admin.auth().createUser = realCreateUser;
    }
  });

  it("validates the payload before creating anything", async () => {
    await assert.rejects(
      invoke("adminA", {
        fullName: "New Admin",
        cafeName: "Cafe A",
        email: "newadmin@test.com",
        phoneNumber: "",
        password: "123", // too short
      }),
      (err) => err.code === "invalid-argument",
    );
    await assert.rejects(
      invoke("adminA", {
        fullName: "",
        cafeName: "Cafe A",
        email: "newadmin@test.com",
        phoneNumber: "",
        password: "secret123",
      }),
      (err) => err.code === "invalid-argument",
    );
  });

  it("maps a duplicate email to already-exists", async () => {
    admin.auth().createUser = async () => {
      const err = new Error("duplicate");
      err.code = "auth/email-already-in-use";
      throw err;
    };
    try {
      await assert.rejects(
        invoke("adminA", {
          fullName: "New Admin",
          cafeName: "Cafe A",
          email: "newadmin@test.com",
          phoneNumber: "",
          password: "secret123",
        }),
        (err) => err.code === "already-exists",
      );
    } finally {
      admin.auth().createUser = realCreateUser;
    }
  });
});
