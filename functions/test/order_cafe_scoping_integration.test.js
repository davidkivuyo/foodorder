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
//   6  Legacy orders (no `cafes`) are unreadable by every admin until the
//      backfill tags them; once tagged, scoping applies
//   7  An admin without a cafeName cannot read scoped orders (but can read
//      cafeless/UNASSIGNED ones)
//   8  Students cannot forge the `cafes` array (no create rule; protected on update)
//   9  placeOrder writes the server-authoritative `cafes` array
//  10  Cafeless orders are tagged UNASSIGNED and are readable by any admin
//  11  onNewOrder notifies only the scoped cafe admin for a legacy order
//      backfilled with cafes
//  12  onNewOrder repairs an EMPTY cafes array (deriving the cafe from items)
//      and notifies the scoped admin
//  13  An UNASSIGNED order can be processed (updated) by any active admin
//  14  An admin without a cafeName can read a cafeless order, but not a
//      cafe-scoped one
//  15  onNewOrder backfill repairs malformed/absent cafes and tags cafeless
//      orders with UNASSIGNED
//
// Additional describe blocks in this suite cover, for the same emulator:
//   • cart serialization lock document (_cart_lock_) write rules
//   • createAdminAccount callable (no self-registration, auth + profile +
//     audit, payload validation, duplicate-email mapping)
//   • reactivateStudent callable (backend-only audit, deduped notification)
//   • audit_logs read scoping (per cafe; cafeless records readable by any
//     admin; students denied)
//
// Note: the excuseNoShow callable has its own dedicated emulator suite
// (test/excuse_no_show_integration.test.js, Phase G Tests 1-14) covering
// cross-cafe/suspended-admin denial, non-NO_SHOW rejection, idempotency
// without duplicate audit/notification documents, and atomic commit — it is
// not repeated here.
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
    // And the scoped query the admin app runs returns only own-cafe orders:
    // the Cafe A order is returned, while the Cafe B order stays excluded.
    await seedOrder("scope-own-q-1", validOrderPayload({ cafes: ["Cafe A"] }));
    const own = await adminDb("adminA")
        .collection("orders")
        .where("cafes", "array-contains", "Cafe A")
        .get();
    assert.equal(own.size, 1, "scoped query returns exactly the Cafe A order");
    assert.equal(own.docs[0].id, "scope-own-q-1");
    assert.equal(own.docs[0].data().cafes[0], "Cafe A");
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

  it("Test 6 — legacy orders (no `cafes`) are unreadable until the backfill "
      + "tags them (no cafeless fallback)", async () => {
    const legacy = validOrderPayload();
    delete legacy.cafes;
    await seedOrder("scope-legacy-1", legacy);
    // No valid cafe scope → NO admin can read the unscoped legacy order
    // (adminA included) until the privileged backfill derives one — there
    // is no universal access to unscoped Cafe A data.
    await assert.rejects(
      adminDb("adminA").collection("orders").doc("scope-legacy-1").get(),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      adminDb("adminB").collection("orders").doc("scope-legacy-1").get(),
      (err) => err.code === "permission-denied",
    );
    // Privileged backfill (Admin SDK) tags the order with its derived cafe;
    // scoping then applies normally: adminA can operate and adminB is denied.
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

  it("Test 10 — cafeless orders are tagged UNASSIGNED and are served by "
      + "any active admin", async () => {
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
    // The `cafes` field carries the UNASSIGNED sentinel — never omitted and
    // never an empty array — so the order has an explicit scoping scope that
    // any admin may serve.
    const snap = await db.collection("orders").doc("scope-place-cafeless").get();
    assert.equal(snap.exists, true);
    assert.deepEqual(
      snap.data().cafes,
      ["UNASSIGNED"],
      "cafeless order must carry the UNASSIGNED scoping sentinel",
    );
    // Every active admin may read a cafeless order through the client rules,
    // so an admin who was notified can always open it.
    const adminASnap = await adminDb("adminA")
        .collection("orders")
        .doc("scope-place-cafeless")
        .get();
    assert.equal(adminASnap.exists, true);
    const adminBSnap = await adminDb("adminB")
        .collection("orders")
        .doc("scope-place-cafeless")
        .get();
    assert.equal(adminBSnap.exists, true);
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

  it("Test 12 — onNewOrder repairs an EMPTY cafes array (deriving the cafe "
      + "from items) and notifies the scoped admin", async () => {
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
    // behaviour: an EMPTY array. The backfill now treats empty/malformed
    // values as needing repair, deriving the cafe from the items.
    const orderId = "scope-empty-cafes-notif";
    const orderData = validOrderPayload({ orderId });
    orderData.cafes = [];
    await seedOrder(orderId, orderData);

    // Invoke the real onNewOrder trigger (document-created event shape).
    const ref = db.collection("orders").doc(orderId);
    const snapshot = { ref, data: () => orderData, exists: true };
    await functionsModule.onNewOrder.run({ data: snapshot, params: { orderId } });

    // The backfill repaired the empty array with the items-derived cafe, so
    // the order is scoped to Cafe A and shows up in Cafe A's admin query.
    const orderSnap = await db.collection("orders").doc(orderId).get();
    assert.deepEqual(orderSnap.data().cafes, ["Cafe A"]);

    const notifs = await db.collection("notifications").get();
    const recipientIds = notifs.docs
        .map((d) => d.data().recipientId);
    assert.deepEqual(
      [...new Set(recipientIds)],
      ["adminA"],
      "order with an empty cafes array must notify its cafe admin (Cafe A)",
    );
  });

  it("Test 13 — an UNASSIGNED order can be processed (updated) by any "
      + "active admin", async () => {
    await seedOrder("scope-unassigned-upd-1", validOrderPayload({
      cafes: ["UNASSIGNED"],
      status: "accepted",
      createdAt: new Date(Date.now() - 3 * 60000),
      cancellationDeadline: new Date(Date.now() - 1000),
    }));
    // Any active admin (even one from a different cafe) may update it.
    await adminDb("adminB")
        .collection("orders")
        .doc("scope-unassigned-upd-1")
        .update({ status: "preparing", updatedAt: new Date() });
    const after = await db.collection("orders").doc("scope-unassigned-upd-1").get();
    assert.equal(after.data().status, "preparing");
  });

  it("Test 14 — an admin without a cafeName can read a cafeless order, "
      + "but not a cafe-scoped one", async () => {
    await seedOrder("scope-nocafe-cafeless", validOrderPayload({
      cafes: ["UNASSIGNED"],
    }));
    const cafelessSnap = await adminDb("adminNoCafe")
        .collection("orders")
        .doc("scope-nocafe-cafeless")
        .get();
    assert.equal(cafelessSnap.exists, true);
    // The cafe-scoped denial from Test 7 still holds.
    await seedOrder("scope-nocafe-scoped-1", validOrderPayload({ cafes: ["Cafe A"] }));
    await assert.rejects(
      adminDb("adminNoCafe")
          .collection("orders")
          .doc("scope-nocafe-scoped-1")
          .get(),
      (err) => err.code === "permission-denied",
    );
  });

  it("Test 15 — onNewOrder backfill repairs malformed/absent cafes and tags "
      + "cafeless orders with UNASSIGNED", async () => {
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

    // Malformed (non-array) value + derivable items → repaired to the
    // derived cafe.
    let orderId = "bf-malformed-1";
    let orderData = validOrderPayload({ orderId });
    orderData.cafes = "Cafe A";
    await seedOrder(orderId, orderData);
    await functionsModule.onNewOrder.run({
      data: { ref: db.collection("orders").doc(orderId), data: () => orderData, exists: true },
      params: { orderId },
    });
    assert.deepEqual(
      (await db.collection("orders").doc(orderId).get()).data().cafes,
      ["Cafe A"],
    );

    // Absent field + nothing derivable → tagged UNASSIGNED.
    orderId = "bf-cafeless-1";
    orderData = validOrderPayload({
      orderId,
      items: [{
        foodItemId: "food_1",
        title: "Rice & Beans",
        price: 3000,
        quantity: 1,
        image: "",
        selectedCafe: null,
      }],
    });
    delete orderData.cafes;
    await seedOrder(orderId, orderData);
    await functionsModule.onNewOrder.run({
      data: { ref: db.collection("orders").doc(orderId), data: () => orderData, exists: true },
      params: { orderId },
    });
    assert.deepEqual(
      (await db.collection("orders").doc(orderId).get()).data().cafes,
      ["UNASSIGNED"],
    );

    // A valid non-empty list is left untouched (idempotent no-op).
    orderId = "bf-valid-1";
    orderData = validOrderPayload({ orderId });
    await seedOrder(orderId, orderData);
    await functionsModule.onNewOrder.run({
      data: { ref: db.collection("orders").doc(orderId), data: () => orderData, exists: true },
      params: { orderId },
    });
    assert.deepEqual(
      (await db.collection("orders").doc(orderId).get()).data().cafes,
      ["Cafe A"],
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

describe("reactivateStudent callable (backend-only audit)", () => {
  function invoke(uid, data) {
    return functionsModule.reactivateStudent.run({ auth: { uid }, data });
  }

  async function seedSuspendedStudent(uid) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc(uid).set({
        fullName: "Suspended Student",
        email: `${uid}@test.com`,
        role: "student",
        accountStatus: "SUSPENDED",
        createdAt: new Date(),
      });
    });
  }

  it("rejects a non-admin caller", async () => {
    await seedSuspendedStudent("studentSuspended1");
    await assert.rejects(
      invoke("student1", { studentId: "studentSuspended1" }),
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
    await seedSuspendedStudent("studentSuspended2");
    await assert.rejects(
      invoke("adminSuspended", { studentId: "studentSuspended2" }),
      (err) => err.code === "permission-denied",
    );
  });

  it("an active admin reactivates a suspended student (flip + audit + notification)",
      async () => {
        await seedSuspendedStudent("studentSuspended3");
        const result = await invoke("adminA", {
          studentId: "studentSuspended3",
          reason: "Reviewed and approved",
        });
        assert.equal(result.success, true);

        const profile = await db.collection("users").doc("studentSuspended3").get();
        assert.equal(profile.data().accountStatus, "ACTIVE");

        // Server-derived identity + timestamp on the immutable audit record.
        const audit = await db
            .collection("audit_logs")
            .where("action", "==", "REACTIVATE")
            .where("studentId", "==", "studentSuspended3")
            .get();
        assert.equal(audit.size, 1, "a REACTIVATE audit record must be written");
        assert.equal(audit.docs[0].data().adminId, "adminA");
        assert.equal(audit.docs[0].data().reason, "Reviewed and approved");
        assert.ok(audit.docs[0].data().timestamp, "server-derived timestamp");

        // Exactly one deduped student notification.
        const notifications = await db
            .collection("notifications")
            .where("eventId", "==", "ACCOUNT_REACTIVATED_studentSuspended3")
            .get();
        assert.equal(notifications.size, 1);
        assert.equal(notifications.docs[0].data().type, "ACCOUNT_REACTIVATED");
        assert.equal(
          notifications.docs[0].data().recipientId, "studentSuspended3");
      });

  it("rejects a target that is not suspended", async () => {
    // student1 is seeded ACTIVE.
    await assert.rejects(
      invoke("adminA", { studentId: "student1" }),
      (err) => err.code === "failed-precondition",
    );
  });

  it("rejects a missing target", async () => {
    await assert.rejects(
      invoke("adminA", { studentId: "ghost-student" }),
      (err) => err.code === "not-found",
    );
  });

  it("validates the payload", async () => {
    await assert.rejects(
      invoke("adminA", { studentId: "" }),
      (err) => err.code === "invalid-argument",
    );
    await assert.rejects(
      invoke("adminA", {}),
      (err) => err.code === "invalid-argument",
    );
  });
});

describe("audit_logs read scoping (per cafe)", () => {
  async function seedAudit(docId, data) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("audit_logs").doc(docId).set(data);
    });
  }

  it("an admin reads an audit record for their own cafe", async () => {
    await seedAudit("scope-audit-1", {
      action: "NO_SHOW_EXCUSED",
      cafeId: "Cafe A",
      adminId: "adminA",
      studentId: "student1",
      note: "private note",
      timestamp: new Date(),
    });
    const snap = await adminDb("adminA")
        .collection("audit_logs").doc("scope-audit-1").get();
    assert.equal(snap.exists, true);
  });

  it("an admin is denied reading a cross-cafe audit record", async () => {
    await seedAudit("scope-audit-2", {
      action: "NO_SHOW_EXCUSED",
      cafeId: "Cafe A",
      adminId: "adminA",
      studentId: "student1",
      note: "private note",
      timestamp: new Date(),
    });
    await assert.rejects(
      adminDb("adminB").collection("audit_logs").doc("scope-audit-2").get(),
      (err) => err.code === "permission-denied",
    );
  });

  it("a cafeless audit record (global action) is readable by any admin", async () => {
    await seedAudit("scope-audit-3", {
      action: "CREATE_ADMIN",
      adminId: "adminA",
      timestamp: new Date(),
    });
    const snapA = await adminDb("adminA")
        .collection("audit_logs").doc("scope-audit-3").get();
    const snapB = await adminDb("adminB")
        .collection("audit_logs").doc("scope-audit-3").get();
    assert.equal(snapA.exists, true);
    assert.equal(snapB.exists, true);
  });

  it("a student cannot read audit records", async () => {
    await seedAudit("scope-audit-4", {
      action: "REACTIVATE",
      timestamp: new Date(),
    });
    await assert.rejects(
      testEnv.authenticatedContext("student1").firestore()
          .collection("audit_logs").doc("scope-audit-4").get(),
      (err) => err.code === "permission-denied",
    );
  });
});
