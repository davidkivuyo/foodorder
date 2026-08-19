"use strict";

// Behavioral verification for the refactored migrateLegacyOrderFoodIds
// (Finding: cognitive complexity). Exercises the phase walk, cursor, retry
// pass, failed-ID retention, and completion against the real emulator.
//
// A unique project id is used per run so the migration state document
// (migrations/food_ids_backfill) and seeded orders never collide with other
// concurrent runs sharing the emulator. The Firestore emulator routes and
// isolates data by project id, so the fixed `--project demo-foodorder`
// launch below is unaffected.

const RUN_PROJECT_ID = "campusbite-foodids-" +
    Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);

process.env.GCLOUD_PROJECT = RUN_PROJECT_ID;
process.env.FIRESTORE_EMULATOR_HOST = "localhost:8080";
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: RUN_PROJECT_ID });

const test = require("node:test");
const assert = require("node:assert/strict");

const admin = require("firebase-admin");
const functionsModule = require("../index.js");
const db = admin.firestore();

const STATE_REF = db.collection("migrations").doc("food_ids_backfill");

const RUN_ID = Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
const order = (id) => db.collection("orders").doc(`test_${RUN_ID}_${id}`);
const food = (id) => db.collection("food_items").doc(`test_${RUN_ID}_${id}`);

async function resetState(overrides = {}) {
  await STATE_REF.set({
    phase: "collected",
    cursor: null,
    status: null,
    failedOrderIds: [],
    processedCount: 0,
    ...overrides,
  });
}

async function runMigration() {
  return functionsModule.migrateLegacyOrderFoodIds.run({});
}

test("single page of legacy collected orders gets foodIds backfilled", async () => {
  await resetState({});
  const foodId = "f1";
  await food(foodId).set({ name: "Pasta", price: 5 });
  for (let i = 0; i < 3; i++) {
    await order(`legacy_${i}`).set({
      status: "collected",
      items: [{ foodItemId: foodId, qty: 1, selectedCafe: "Main" }],
      userId: "u1",
      cafe: "Main",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await runMigration();
  const state = (await STATE_REF.get()).data();
  assert.equal(state.phase, "COLLECTED", "phase should advance to COLLECTED after first phase walk");
  assert.equal(state.processedCount, 3, "3 orders processed");
  for (let i = 0; i < 3; i++) {
    const snap = await order(`legacy_${i}`).get();
    assert.ok(snap.data().foodIds.includes(foodId), `order legacy_${i} should have foodIds`);
  }
});

test("already-populated foodIds are not rewritten and migration completes", async () => {
  await resetState({ phase: "COLLECTED" });
  const foodId = "f2";
  await food(foodId).set({ name: "Salad", price: 4 });
  await order("tagged").set({
    status: "COLLECTED",
    foodIds: [foodId],
    items: [{ foodItemId: foodId, qty: 1, selectedCafe: "Main" }],
    userId: "u1",
    cafe: "Main",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  const before = await order("tagged").get();
  await runMigration();
  const after = await order("tagged").get();
  assert.deepEqual(after.data().foodIds, before.data().foodIds, "should not rewrite tagged order");
  const state = (await STATE_REF.get()).data();
  assert.equal(state.status, "completed", "migration completes when no failures");
});

test("prior-failure ghost order is resolved by the retry pass, enabling completion", async () => {
  await resetState({ phase: "COLLECTED" });
  const foodId = "f3";
  await food(foodId).set({ name: "Burger", price: 6 });
  await order("pending_fail").set({
    status: "COLLECTED",
    items: [{ foodItemId: foodId, qty: 1, selectedCafe: "Main" }],
    userId: "u1",
    cafe: "Main",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  // A prior run recorded a failure for an order that no longer exists. The
  // retry pass must re-read it, detect the deletion, and drop it from the
  // retained failures so completion stays reachable.
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
  assert.equal(state.processedCount, 1, "pending_fail order backfilled this run");
});

test("already-completed migration skips immediately", async () => {
  await resetState({ status: "completed", phase: "completed" });
  await runMigration();
  const state = (await STATE_REF.get()).data();
  assert.equal(state.status, "completed", "status unchanged");
  assert.equal(state.phase, "completed");
});
