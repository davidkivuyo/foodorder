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

// Phase B — ORDER CANCELLATION & 2-MINUTE WINDOW: executable
// emulator/integration coverage.
//
// This suite runs the REAL Firestore emulator with the REAL firestore.rules
// loaded and exercises the REAL exported `cancelOrder` callable handler
// against the emulator-backed Admin SDK, complementing the static guardrails
// in test/order_cancellation_foundation_test.dart.
//
// Run (requires Java 21+ — e.g. JAVA_HOME=/usr/lib/jvm/java-25-openjdk):
//   npm run test:cancellation:integration   (inside functions/)
// or, from the project root:
//   JAVA_HOME=/usr/lib/jvm/java-25-openjdk firebase emulators:exec \
//     --only firestore --project demo-foodorder \
//     "node --test functions/test/order_cancellation_integration.test.js"

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
const { serverTimestamp } = require("firebase/firestore");

const RULES_FILE = path.join(__dirname, "../../firestore.rules");
const CANCELLATION_WINDOW_MINUTES = 2;

let testEnv;

// ── Fixtures ────────────────────────────────────────────────────────────────

// Base order payload. Rules-based creates override createdAt with
// serverTimestamp() (the create rule requires it to equal request.time);
// seeded (rules-disabled) writes keep the literal Date default, which the
// Admin SDK persists as a real Timestamp.
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

/** Build the request shape consumed by an onCall handler. */
function callableRequest(uid, data) {
  return { auth: { uid }, data };
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
    await seed.collection("users").doc("student2").set({
      fullName: "Second Student",
      email: "student2@test.com",
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

describe("Firestore rules — cancellation authorization behaviour", () => {
  it("lets a verified student create a pending order with server-authoritative "
      + "timestamps (Test 1)", async () => {
    await studentDb()
      .collection("orders")
      .doc("cancel-rule-ok-1")
      .set(validOrderPayload({ createdAt: serverTimestamp() }));
    const snap = await db.collection("orders").doc("cancel-rule-ok-1").get();
    assert.equal(snap.data().status, "pending");
    // The client may not supply a cancellationDeadline on create — the
    // onNewOrder trigger writes the authoritative createdAt + 2 min later.
    assert.equal(snap.data().cancellationDeadline, undefined);
  });

  it("enforces student order read isolation — owner reads allowed, other "
      + "students denied direct get and list access", async () => {
    // An order owned by student1 (validOrderPayload defaults to student1).
    await seedOrder("cancel-isolation-1", validOrderPayload());

    // Owner (student1) may read the order directly.
    const ownerSnap = await studentDb("student1")
      .collection("orders")
      .doc("cancel-isolation-1")
      .get();
    assert.equal(ownerSnap.exists, true);
    assert.equal(ownerSnap.data().status, "pending");

    // Another student (student2) is denied a direct get of student1's order.
    // Read denials surface as code "permission-denied" without the literal
    // PERMISSION_DENIED text, so match on the error code.
    await assert.rejects(
      studentDb("student2")
        .collection("orders")
        .doc("cancel-isolation-1")
        .get(),
      (err) => err.code === "permission-denied",
    );

    // And denied list access that could match student1's order: an
    // unconstrained collection query and a query scoped to the owner are
    // both rejected because they may expose documents the caller cannot read.
    await assert.rejects(
      studentDb("student2").collection("orders").get(),
      (err) => err.code === "permission-denied",
    );
    await assert.rejects(
      studentDb("student2")
        .collection("orders")
        .where("studentId", "==", "student1")
        .get(),
      (err) => err.code === "permission-denied",
    );

    // A query scoped to the caller's own studentId stays allowed and returns
    // only their orders (empty here) — isolation, not blanket denial.
    const scoped = await studentDb("student2")
      .collection("orders")
      .where("studentId", "==", "student2")
      .get();
    assert.equal(scoped.size, 0);
  });

  it("denies a student who tries to modify cancellationDeadline "
      + "(Test 16)", async () => {
    await seedOrder("cancel-rule-upd-1", validOrderPayload());
    await assert.rejects(
      studentDb().collection("orders").doc("cancel-rule-upd-1").update({
        cancellationDeadline: new Date(Date.now() + 10 * 60000),
      }),
      /PERMISSION_DENIED/,
    );
    // Cancellation metadata is forge-proof too.
    await assert.rejects(
      studentDb().collection("orders").doc("cancel-rule-upd-1").update({
        cancelledAt: new Date(),
        cancelledBy: "student1",
      }),
      /PERMISSION_DENIED/,
    );
    const after = await orderById("cancel-rule-upd-1");
    assert.equal(after.cancelledAt, undefined);
  });

  it("denies student order create with forged cancelledAt/cancelledBy",
      async () => {
    // The base payload is otherwise valid (server-resolved createdAt, no
    // deadline), so the denial is attributable to the forged field.
    await assert.rejects(
      studentDb().collection("orders").doc("cancel-rule-forge-1").set(
        validOrderPayload({
          createdAt: serverTimestamp(),
          cancelledAt: new Date(),
        }),
      ),
      /PERMISSION_DENIED/,
    );
    await assert.rejects(
      studentDb().collection("orders").doc("cancel-rule-forge-2").set(
        validOrderPayload({
          createdAt: serverTimestamp(),
          cancelledBy: "student1",
        }),
      ),
      /PERMISSION_DENIED/,
    );
  });

  it("denies student order create with a client-literal createdAt — only "
      + "the server-resolved sentinel passes (protects the age gate)", async () => {
    // createdAt must equal request.time, which only FieldValue.serverTimestamp()
    // produces. Any literal client timestamp — backdated or forward-dated —
    // is rejected, so the missing-deadline age gate in
    // cancellationWindowPassed() cannot be bypassed by choosing createdAt.
    for (const forgedCreatedAt of [
      new Date(Date.now() - 10 * 60000), // backdated
      new Date(Date.now() + 60 * 60000), // forward-dated
    ]) {
      await assert.rejects(
        studentDb().collection("orders").doc("cancel-rule-forge-3").set(
          validOrderPayload({ createdAt: forgedCreatedAt }),
        ),
        (err) => err.code === "permission-denied",
        "literal createdAt must be denied on create",
      );
    }
  });

  it("denies student order create with an EARLY client-supplied "
      + "cancellationDeadline", async () => {
    // The authoritative deadline (createdAt + 2 min) is written only by the
    // onNewOrder trigger. A client that sends any deadline — here one well
    // before the intended window — must be rejected on create.
    await assert.rejects(
      studentDb().collection("orders").doc("cancel-rule-forge-early").set(
        validOrderPayload({
          createdAt: serverTimestamp(),
          cancellationDeadline: new Date(Date.now() - 60 * 1000),
        }),
      ),
      (err) => err.code === "permission-denied",
      "early client deadline must be denied on create",
    );
  });

  it("denies student order create with a DELAYED client-supplied "
      + "cancellationDeadline", async () => {
    // A client deadline far beyond the intended 2-minute window must also be
    // rejected — the field is backend-written exclusively.
    await assert.rejects(
      studentDb().collection("orders").doc("cancel-rule-forge-delayed").set(
        validOrderPayload({
          createdAt: serverTimestamp(),
          cancellationDeadline: new Date(Date.now() + 10 * 60000),
        }),
      ),
      (err) => err.code === "permission-denied",
      "delayed client deadline must be denied on create",
    );
  });

  it("denies admin acceptance before the cancellation window passes "
      + "(Test 5)", async () => {
    await seedOrder("cancel-accept-early-1", validOrderPayload({
      cancellationDeadline: new Date(Date.now() + 90 * 1000), // +1m30s
    }));
    await assert.rejects(
      adminDb().collection("orders").doc("cancel-accept-early-1").update({
        status: "accepted",
        updatedAt: new Date(),
      }),
      /PERMISSION_DENIED/,
    );
    const after = await orderById("cancel-accept-early-1");
    assert.equal(after.status, "pending");
  });

  it("allows admin acceptance after the cancellation window passes "
      + "(Test 6)", async () => {
    await seedOrder("cancel-accept-late-1", validOrderPayload({
      cancellationDeadline: new Date(Date.now() - 1000), // already passed
    }));
    await adminDb().collection("orders").doc("cancel-accept-late-1").update({
      status: "accepted",
      updatedAt: new Date(),
    });
    const after = await orderById("cancel-accept-late-1");
    assert.equal(after.status, "accepted");
  });

  it("lets an AGED legacy order (no cancellationDeadline, created over 2 min "
      + "ago) be accepted (backward compatibility)", async () => {
    // Genuinely aged legacy order: created long before the 2-minute window
    // would have elapsed, so acceptance no longer defeats the window.
    const legacy = validOrderPayload({
      createdAt: new Date(Date.now() - 10 * 60000),
    });
    delete legacy.cancellationDeadline;
    await seedOrder("cancel-legacy-1", legacy);
    await adminDb().collection("orders").doc("cancel-legacy-1").update({
      status: "accepted",
      updatedAt: new Date(),
    });
    const after = await orderById("cancel-legacy-1");
    assert.equal(after.status, "accepted");
  });

  it("denies acceptance of a FRESH order without a cancellationDeadline "
      + "(no instant-accept bypass)", async () => {
    // A legacy client that omits the deadline on a brand-new order must not
    // be able to have it accepted instantly — the missing deadline is
    // treated as an active window until the order has aged past 2 minutes.
    const legacy = validOrderPayload(); // createdAt defaults to now
    delete legacy.cancellationDeadline;
    await seedOrder("cancel-legacy-fresh-1", legacy);

    await assert.rejects(
      adminDb().collection("orders").doc("cancel-legacy-fresh-1").update({
        status: "accepted",
        updatedAt: new Date(),
      }),
      (err) => err.code === "permission-denied",
      "fresh deadline-less order must not be accepted instantly",
    );
    const after = await orderById("cancel-legacy-fresh-1");
    assert.equal(after.status, "pending");
  });

  it("denies every admin transition out of the terminal cancelled state "
      + "(Tests 36)", async () => {
    // Seed a cancelled order exactly as the cancelOrder callable leaves it:
    // terminal status plus the immutable cancellation metadata.
    await seedOrder("cancel-terminal-1", validOrderPayload({
      status: "cancelled",
      cancelledAt: new Date(Date.now() - 60000),
      cancelledBy: "student1",
      cancellationReason: "Changed my mind",
    }));

    // CANCELLED is terminal: every forward transition an admin might attempt
    // must be denied by validOrderStatusTransition(), which has no branch
    // leaving 'cancelled'.
    const forbiddenTransitions = [
      "accepted",
      "preparing",
      "ready",
      "collected",
      "no_show",
    ];
    for (const target of forbiddenTransitions) {
      await assert.rejects(
        adminDb().collection("orders").doc("cancel-terminal-1").update({
          status: target,
          updatedAt: new Date(),
        }),
        (err) => err.code === "permission-denied",
        `cancelled -> ${target} must be denied`,
      );
    }

    // The order and its cancellation metadata are untouched.
    const after = await orderById("cancel-terminal-1");
    assert.equal(after.status, "cancelled");
    assert.equal(after.cancelledBy, "student1");
    assert.equal(after.cancellationReason, "Changed my mind");
  });
});

describe("cancelOrder callable — student cancellation flow", () => {
  it("cancels the student's own pending order within the window "
      + "(Tests 2 & 3)", async () => {
    await seedOrder("cancel-flow-1", validOrderPayload({
      cancellationDeadline: new Date(Date.now() + 90 * 1000),
    }));

    const result = await functionsModule.cancelOrder.run(callableRequest(
      "student1",
      { orderId: "cancel-flow-1", reason: "Changed my mind" },
    ));

    assert.equal(result.success, true);
    const after = await orderById("cancel-flow-1");
    assert.equal(after.status, "cancelled");
    assert.equal(after.cancelledBy, "student1");
    assert.equal(after.cancellationReason, "Changed my mind");
    assert.ok(after.cancelledAt instanceof admin.firestore.Timestamp, "cancelledAt written");
    // The student gets exactly one cancellation notification.
    assert.equal(await countNotifications("ORDER_CANCELLED_cancel-flow-1"), 1);
  });

  it("rejects cancellation after the deadline has passed (Test 4)", async () => {
    await seedOrder("cancel-flow-2", validOrderPayload({
      // The authoritative window is derived from the server-resolved
      // createdAt (createdAt + 2 min), not from the display-only stored
      // deadline. Age the order past the window so cancellation is rejected.
      createdAt: new Date(Date.now() - 3 * 60000), // placed 3 min ago
      cancellationDeadline: new Date(Date.now() - 1000),
    }));

    await assert.rejects(
      functionsModule.cancelOrder.run(callableRequest(
        "student1",
        { orderId: "cancel-flow-2" },
      )),
      (err) => err.code === "failed-precondition",
    );
    const after = await orderById("cancel-flow-2");
    assert.equal(after.status, "pending");
  });

  it("cancels a FRESH order before the onNewOrder trigger has written "
      + "cancellationDeadline (pre-trigger window)", async () => {
    // A brand new rules-created order carries NO cancellationDeadline — the
    // onNewOrder trigger writes createdAt + 2 min asynchronously. The
    // callable must derive the same window from the server-authoritative
    // createdAt (rules require createdAt == request.time) so a student can
    // cancel immediately after placing an order, before the trigger lands.
    await seedOrder("cancel-flow-fresh-1", validOrderPayload({
      createdAt: new Date(Date.now() - 1000), // placed ~1s ago, trigger pending
    }));

    const result = await functionsModule.cancelOrder.run(callableRequest(
      "student1",
      { orderId: "cancel-flow-fresh-1", reason: "Changed my mind" },
    ));

    assert.equal(result.success, true);
    const after = await orderById("cancel-flow-fresh-1");
    assert.equal(after.status, "cancelled");
    assert.equal(after.cancelledBy, "student1");
    assert.ok(after.cancelledAt instanceof admin.firestore.Timestamp);
  });

  it("rejects cancelling a deadline-less order whose DERIVED createdAt "
      + "window has already passed", async () => {
    // Same pre-trigger shape (no cancellationDeadline), but the order is
    // older than the 2-minute window: the derived createdAt + 2 min deadline
    // has passed, so cancellation must be rejected exactly as if the trigger
    // had written the deadline.
    await seedOrder("cancel-flow-fresh-expired-1", validOrderPayload({
      createdAt: new Date(Date.now() - 3 * 60000), // placed 3 min ago
    }));

    await assert.rejects(
      functionsModule.cancelOrder.run(callableRequest(
        "student1",
        { orderId: "cancel-flow-fresh-expired-1" },
      )),
      (err) => err.code === "failed-precondition",
    );
    const after = await orderById("cancel-flow-fresh-expired-1");
    assert.equal(after.status, "pending");
  });

  it("rejects cancelling an accepted order (Test 8)", async () => {
    await seedOrder("cancel-flow-8", validOrderPayload({
      status: "accepted",
      cancellationDeadline: new Date(Date.now() + 90 * 1000),
    }));
    await assert.rejects(
      functionsModule.cancelOrder.run(callableRequest(
        "student1",
        { orderId: "cancel-flow-8" },
      )),
      (err) => err.code === "failed-precondition",
    );
  });

  it("rejects cancelling a preparing order (Test 9)", async () => {
    await seedOrder("cancel-flow-9", validOrderPayload({
      status: "preparing",
      cancellationDeadline: new Date(Date.now() + 90 * 1000),
    }));
    await assert.rejects(
      functionsModule.cancelOrder.run(callableRequest(
        "student1",
        { orderId: "cancel-flow-9" },
      )),
      (err) => err.code === "failed-precondition",
    );
  });

  it("rejects cancelling a ready order (Test 10)", async () => {
    await seedOrder("cancel-flow-10", validOrderPayload({
      status: "ready",
      cancellationDeadline: new Date(Date.now() + 90 * 1000),
    }));
    await assert.rejects(
      functionsModule.cancelOrder.run(callableRequest(
        "student1",
        { orderId: "cancel-flow-10" },
      )),
      (err) => err.code === "failed-precondition",
    );
  });

  it("rejects cancelling a collected order (Test 11)", async () => {
    await seedOrder("cancel-flow-11", validOrderPayload({
      status: "collected",
      cancellationDeadline: new Date(Date.now() + 90 * 1000),
    }));
    await assert.rejects(
      functionsModule.cancelOrder.run(callableRequest(
        "student1",
        { orderId: "cancel-flow-11" },
      )),
      (err) => err.code === "failed-precondition",
    );
  });

  it("rejects cancelling a no_show order (Test 12)", async () => {
    await seedOrder("cancel-flow-12", validOrderPayload({
      status: "no_show",
      cancellationDeadline: new Date(Date.now() + 90 * 1000),
    }));
    await assert.rejects(
      functionsModule.cancelOrder.run(callableRequest(
        "student1",
        { orderId: "cancel-flow-12" },
      )),
      (err) => err.code === "failed-precondition",
    );
  });

  it("rejects cancelling another student's order (Test 15)", async () => {
    await seedOrder("cancel-flow-15", validOrderPayload({
      cancellationDeadline: new Date(Date.now() + 90 * 1000),
    }));
    await assert.rejects(
      functionsModule.cancelOrder.run(callableRequest(
        "student2",
        { orderId: "cancel-flow-15" },
      )),
      (err) => err.code === "permission-denied",
    );
    const after = await orderById("cancel-flow-15");
    assert.equal(after.status, "pending");
  });

  it("rejects unknown order ids (not-found)", async () => {
    await assert.rejects(
      functionsModule.cancelOrder.run(callableRequest(
        "student1",
        { orderId: "cancel-ghost-1" },
      )),
      (err) => err.code === "not-found",
    );
  });

  it("rejects non-preset cancellation reasons", async () => {
    await seedOrder("cancel-flow-reason-1", validOrderPayload());
    await assert.rejects(
      functionsModule.cancelOrder.run(callableRequest(
        "student1",
        { orderId: "cancel-flow-reason-1", reason: "custom free text" },
      )),
      (err) => err.code === "invalid-argument",
    );
  });

  it("rejects an over-long cancellation reason", async () => {
    await seedOrder("cancel-flow-longreason-1", validOrderPayload());
    await assert.rejects(
      functionsModule.cancelOrder.run(callableRequest(
        "student1",
        {
          orderId: "cancel-flow-longreason-1",
          reason: "x".repeat(201),
        },
      )),
      (err) => err.code === "invalid-argument",
    );
  });
});

describe("cancellation vs acceptance race", () => {
  // The two transitions are mutually exclusive by design: the cancel
  // callable requires the window still open (now < cancellationDeadline),
  // while the acceptance rule requires it passed (deadline <= request.time).
  // So a genuine contention test needs a boundary fixture that makes ONE
  // side eligible, then races both transitions concurrently and asserts
  // exactly one succeeds — neither ordering is structurally impossible.

  it("only one transition succeeds when the window is open — cancel wins "
      + "(Test 7a)", async () => {
    // Window still open: the student may cancel; the rules deny an early
    // admin acceptance (pending -> accepted needs the deadline passed).
    const payload = validOrderPayload({
      cancellationDeadline: new Date(Date.now() + 90 * 1000),
    });
    await seedOrder("cancel-race-1", payload);

    // The cancel callable writes with the Admin SDK (no rules check), while
    // the admin accept goes through the rules. Whichever commits first wins;
    // the final status must be exactly one of cancelled | accepted, never
    // both and never a mix of their fields.
    const cancelling = functionsModule.cancelOrder.run(callableRequest(
      "student1",
      { orderId: "cancel-race-1", reason: "Other" },
    ));
    const accepting = adminDb()
      .collection("orders")
      .doc("cancel-race-1")
      .update({ status: "accepted", updatedAt: new Date() });

    const [cancelResult, acceptResult] = await Promise.allSettled([
      cancelling,
      accepting,
    ]);

    // Exactly one transition succeeds: the cancel. The accept is
    // rules-denied (window not passed / order already cancelled).
    assert.equal(cancelResult.status, "fulfilled");
    assert.equal(cancelResult.value.success, true);
    assert.equal(acceptResult.status, "rejected");
    const acceptDenial = String(acceptResult.reason.code || "")
      + " " + String(acceptResult.reason.message || "");
    assert.match(
      acceptDenial,
      /permission-denied|PERMISSION_DENIED/i,
      "accept must be rules-denied while the window is open",
    );

    const after = await orderById("cancel-race-1");
    assert.equal(after.status, "cancelled");
    assert.equal(after.cancelledBy, "student1");
    assert.equal(after.cancellationReason, "Other");
    assert.ok(after.cancelledAt instanceof admin.firestore.Timestamp);
  });

  it("only one transition succeeds when the window has passed — accept wins "
      + "(Test 7b)", async () => {
    // Window closed: the admin may accept (deadline passed), while the
    // cancel callable rejects with failed-precondition. The window is
    // derived from the server-authoritative createdAt (createdAt + 2 min),
    // so the fixture must age the order itself — a past stored deadline
    // alone no longer closes the window.
    const payload = validOrderPayload({
      createdAt: new Date(Date.now() - 3 * 60000), // placed 3 min ago
      cancellationDeadline: new Date(Date.now() - 1000),
    });
    await seedOrder("cancel-race-2", payload);

    const cancelling = functionsModule.cancelOrder.run(callableRequest(
      "student1",
      { orderId: "cancel-race-2", reason: "Other" },
    ));
    const accepting = adminDb()
      .collection("orders")
      .doc("cancel-race-2")
      .update({ status: "accepted", updatedAt: new Date() });

    const [cancelResult, acceptResult] = await Promise.allSettled([
      cancelling,
      accepting,
    ]);

    // Exactly one transition succeeds: the accept. The cancel is rejected
    // either because the deadline has passed or because the order is no
    // longer pending — both surface as failed-precondition.
    assert.equal(acceptResult.status, "fulfilled");
    assert.equal(cancelResult.status, "rejected");
    assert.equal(cancelResult.reason.code, "failed-precondition");

    const after = await orderById("cancel-race-2");
    assert.equal(after.status, "accepted");
    // An accepted order must not carry cancellation metadata.
    assert.equal(after.cancelledAt, undefined);
    assert.equal(after.cancelledBy, undefined);
    assert.equal(after.cancellationReason, undefined);
  });
});

describe("cancelled orders and the no-show engine (Tests 13 & 14)", () => {
  it("a cancelled order never becomes no_show when its pickup deadline "
      + "passes", async () => {
    // A cancelled order that would otherwise have expired stays cancelled.
    await seedOrder("cancel-ns-1", validOrderPayload({
      status: "cancelled",
      cancelledAt: new Date(Date.now() - 60000),
      cancelledBy: "student1",
      cancellationReason: "Changed my mind",
      cancellationDeadline: new Date(Date.now() - 30 * 1000),
    }));
    // And a real ready order with an expired deadline still processes,
    // proving the processor itself is not broken.
    await seedOrder("cancel-ns-2", validOrderPayload({
      status: "ready",
      deadlineStatus: "ACTIVE",
      pickupDeadline: new Date(Date.now() - 5 * 60000),
    }));

    await functionsModule.processExpiredPickups.run({});

    const cancelled = await orderById("cancel-ns-1");
    assert.equal(cancelled.status, "cancelled");
    assert.equal(cancelled.deadlineStatus, "NOT_READY");
    assert.equal(cancelled.noShowProcessed, undefined);
    assert.equal(await countNotifications("ORDER_NO_SHOW_cancel-ns-1"), 0);

    const processed = await orderById("cancel-ns-2");
    assert.equal(processed.status, "no_show");
  });

  it("cancellation metadata is never overwritten by the expiry processor",
      async () => {
    await seedOrder("cancel-ns-3", validOrderPayload({
      status: "cancelled",
      cancelledAt: new Date(Date.now() - 60000),
      cancelledBy: "student1",
      cancellationReason: "Ordered by mistake",
    }));
    await functionsModule.processExpiredPickups.run({});
    const after = await orderById("cancel-ns-3");
    assert.equal(after.status, "cancelled");
    assert.equal(after.cancelledBy, "student1");
    assert.equal(after.cancellationReason, "Ordered by mistake");
  });
});

describe("onNewOrder — authoritative cancellation deadline", () => {
  it("corrects a skewed client cancellationDeadline to createdAt + 2 min",
      async () => {
    const created = new Date(Date.now() - 30000);
    await seedOrder("cancel-deadline-1", validOrderPayload({
      createdAt: created,
      // Client estimate is wildly wrong (10 minutes ahead).
      cancellationDeadline: new Date(created.getTime() + 10 * 60000),
    }));

    const ref = db.collection("orders").doc("cancel-deadline-1");
    const createdData = await orderById("cancel-deadline-1");
    await functionsModule.onNewOrder.run({
      data: {
        data: () => createdData,
        ref,
      },
      params: { orderId: "cancel-deadline-1" },
    });

    const after = await orderById("cancel-deadline-1");
    assert.ok(
      after.cancellationDeadline instanceof admin.firestore.Timestamp,
      "deadline rewritten as a server timestamp",
    );
    assert.equal(
      Math.round((toMillis(after.cancellationDeadline) - toMillis(created)) / 60000),
      CANCELLATION_WINDOW_MINUTES,
      "authoritative deadline is createdAt + 2 minutes",
    );
  });
});
