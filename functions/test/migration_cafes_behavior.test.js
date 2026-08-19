"use strict";

// Behavioral verification for the refactored migrateLegacyOrderCafes
// (complexity reduction). Exercises the full walk, cursor, retry pass,
// ghost-failure resolution, and completion against the real emulator.

process.env.GCLOUD_PROJECT = "demo-foodorder";
process.env.FIRESTORE_EMULATOR_HOST = "localhost:8080";
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: "demo-foodorder" });

const test = require("node:test");
const assert = require("node:assert/strict");

const admin = require("firebase-admin");
const functionsModule = require("../index.js");
const db = admin.firestore();

const STATE_REF = db.collection("migrations").doc("order_cafes_backfill");

const RUN_ID = Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
const order = (id) => db.collection("orders").doc(`test_${RUN_ID}_${id}`);

async function resetState(overrides = {}) {
  await STATE_REF.set({
    cursor: null,
    status: null,
    failedOrderIds: [],
    processedCount: 0,
    ...overrides,
  });
}

async function runMigration() {
  return functionsModule.migrateLegacyOrderCafes.run({});
}

test("legacy orders across statuses get cafes backfilled", async () => {
  await resetState({});
  const statuses = ["pending", "accepted", "preparing", "ready", "collected"];
  for (let i = 0; i < statuses.length; i++) {
    await order(`legacy_${i}`).set({
      status: statuses[i],
      items: [{ foodItemId: "f1", qty: 1, selectedCafe: "Main Cafe" }],
      userId: "u1",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await runMigration();
  const state = (await STATE_REF.get()).data();
  assert.equal(state.status, "completed", "migration completes on failure-free final page");
  assert.equal(state.processedCount, 5, "5 orders processed");
  for (let i = 0; i < statuses.length; i++) {
    const snap = await order(`legacy_${i}`).get();
    assert.deepEqual(snap.data().cafes, ["Main Cafe"], `order legacy_${i} should have derived cafes`);
  }
});

test("cafeless orders receive the UNASSIGNED sentinel", async () => {
  await resetState({});
  await order("cafeless").set({
    status: "pending",
    items: [{ foodItemId: "f1", qty: 1 }],
    userId: "u1",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await runMigration();
  const snap = await order("cafeless").get();
  assert.deepEqual(snap.data().cafes, ["UNASSIGNED"], "cafeless order tagged with sentinel");
});

test("valid cafes list is not rewritten and migration completes", async () => {
  await resetState({});
  await order("tagged").set({
    status: "ready",
    cafes: ["Main Cafe"],
    items: [{ foodItemId: "f1", qty: 1, selectedCafe: "Main Cafe" }],
    userId: "u1",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  const before = await order("tagged").get();
  await runMigration();
  const after = await order("tagged").get();
  assert.deepEqual(after.data().cafes, before.data().cafes, "should not rewrite valid cafes");
  const state = (await STATE_REF.get()).data();
  assert.equal(state.status, "completed", "migration completes when no failures");
});

test("prior-failure ghost order is resolved by the retry pass", async () => {
  await resetState({});
  await order("pending").set({
    status: "pending",
    items: [{ foodItemId: "f1", qty: 1, selectedCafe: "Main Cafe" }],
    userId: "u1",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await STATE_REF.update({
    failedOrderIds: [`test_${RUN_ID}_ghost`],
  });
  await runMigration();
  const state = (await STATE_REF.get()).data();
  assert.ok(
    !state.failedOrderIds.includes(`test_${RUN_ID}_ghost`),
    "deleted order resolved and dropped by retry pass",
  );
  assert.equal(state.status, "completed", "no failures remain, so migration completes");
  assert.equal(state.processedCount, 1, "pending order backfilled this run");
});

test("already-completed migration skips immediately", async () => {
  await resetState({ status: "completed" });
  await runMigration();
  const state = (await STATE_REF.get()).data();
  assert.equal(state.status, "completed", "status unchanged");
});
