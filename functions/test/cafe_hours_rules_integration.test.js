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

// Operating-hour write contract: executable emulator coverage for the
// validOperatingHour() rule. Runs the REAL Firestore emulator with the REAL
// firestore.rules loaded and asserts which cafe operating-hour writes commit
// under an authenticated admin context.
//
// Run (requires Java 21+ — e.g. JAVA_HOME=/usr/lib/jvm/java-25-openjdk):
//   npm run test:cafe-hours:integration   (inside functions/)
// or, from the project root:
//   JAVA_HOME=/usr/lib/jvm/java-25-openjdk firebase emulators:exec \
//     --only firestore --project demo-foodorder \
//     "node --test functions/test/cafe_hours_rules_integration.test.js"

"use strict";

process.env.GCLOUD_PROJECT = "demo-foodorder";
process.env.FIRESTORE_EMULATOR_HOST = "localhost:8080";

const fs = require("fs");
const path = require("path");
const { describe, it, before, after } = require("node:test");
const assert = require("node:assert");

const { initializeTestEnvironment } = require("@firebase/rules-unit-testing");
const { GeoPoint } = require("@firebase/firestore");

const RULES_FILE = path.join(__dirname, "../../firestore.rules");

let testEnv;

function adminDb() {
  // admin1 is seeded as role=admin, ACTIVE → isAdmin() passes.
  return testEnv.authenticatedContext("admin1").firestore();
}

function cafeDoc(overrides = {}) {
  return {
    name: "Cafe A",
    location: "Main Campus",
    createdAt: new Date(),
    ...overrides,
  };
}

async function expectWriteAccepted(ref, data) {
  await assert.doesNotReject(() => ref.set(data));
}

async function expectWriteDenied(ref, data) {
  await assert.rejects(() => ref.set(data), /PERMISSION_DENIED/);
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-foodorder",
    firestore: {
      rules: fs.readFileSync(RULES_FILE, "utf8"),
      host: "localhost",
      port: 8080,
    },
  });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("users").doc("admin1").set({
      fullName: "Admin One",
      email: "admin1@test.com",
      role: "admin",
      cafeName: "Cafe A",
      accountStatus: "ACTIVE",
      strikeCount: 0,
      strikePercentage: 0,
      createdAt: new Date(),
    });
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe("Firestore rules — cafe operating-hour writes (validOperatingHour)", () => {
  it("accepts valid boundary hour strings", async () => {
    const db = adminDb();
    const cases = [
      { openAt: "00:00", closingAt: "23:59" },
      { openAt: "8:05", closingAt: "9:59" },
      { openAt: "08:05", closingAt: "21:30" },
      { openAt: "0:00", closingAt: "23:59" },
      { openAt: "23:59", closingAt: "00:00" }, // overnight window
    ];
    for (const [i, hours] of cases.entries()) {
      await expectWriteAccepted(
        db.collection("cafes").doc(`cafe-valid-${i}`),
        cafeDoc(hours),
      );
    }
  });

  it("accepts a GeoPoint geoLocation on cafe writes", async () => {
    const db = adminDb();
    await expectWriteAccepted(
      db.collection("cafes").doc("cafe-geo-ok"),
      cafeDoc({
        openAt: "08:00",
        closingAt: "17:00",
        geoLocation: new GeoPoint(36.8167, -1.2864),
      }),
    );
  });

  it("rejects a non-GeoPoint geoLocation on cafe writes", async () => {
    const db = adminDb();
    await expectWriteDenied(
      db.collection("cafes").doc("cafe-geo-bad"),
      cafeDoc({
        openAt: "08:00",
        closingAt: "17:00",
        geoLocation: { latitude: 36.8167, longitude: -1.2864 },
      }),
    );
  });

  it("rejects malformed or out-of-range operating hours", async () => {
    const db = adminDb();
    const malformed = [
      { openAt: "8", closingAt: "21:00" },
      { openAt: "8:5", closingAt: "21:00" },
      { openAt: "08:5", closingAt: "21:00" },
      { openAt: "8:05:30", closingAt: "21:00" },
      { openAt: ":05", closingAt: "21:00" },
      { openAt: "8:", closingAt: "21:00" },
      { openAt: "8 05", closingAt: "21:00" },
      { openAt: "24:00", closingAt: "21:00" },
      { openAt: "23:60", closingAt: "21:00" },
      { openAt: "-1:00", closingAt: "21:00" },
      { openAt: "8:00a", closingAt: "21:00" },
      { openAt: "21:00", closingAt: "30:00" },
      { openAt: "21:00", closingAt: "12:99" },
      // Non-string values (number, boolean) are never accepted.
      { openAt: 800, closingAt: "21:00" },
      { openAt: true, closingAt: "21:00" },
      // A Timestamp cannot carry a timezone-free time-of-day.
      { openAt: new Date(2026, 0, 1, 8, 0), closingAt: "21:00" },
    ];
    for (const [i, hours] of malformed.entries()) {
      await expectWriteDenied(
        db.collection("cafes").doc(`cafe-malformed-${i}`),
        cafeDoc(hours),
      );
    }
  });

  it("rejects malformed hours on an update write as well as a create", async () => {
    const db = adminDb();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("cafes")
        .doc("cafe-update")
        .set(cafeDoc({ openAt: "08:00", closingAt: "17:00" }));
    });
    const ref = db.collection("cafes").doc("cafe-update");
    // A valid update is accepted.
    await assert.doesNotReject(() => ref.update({ openAt: "08:30" }));
    // An out-of-range update is denied.
    await assert.rejects(() => ref.update({ closingAt: "25:00" }), /PERMISSION_DENIED/);
    // A malformed partial update is denied.
    await assert.rejects(() => ref.update({ openAt: "8:5" }), /PERMISSION_DENIED/);
  });

  it("rejects a non-admin writing operating hours", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc("student1").set({
        fullName: "Test Student",
        email: "student1@test.com",
        role: "student",
        accountStatus: "ACTIVE",
        strikeCount: 0,
        strikePercentage: 0,
        createdAt: new Date(),
      });
    });
    const studentRulesDb = testEnv
      .authenticatedContext("student1", { email_verified: true })
      .firestore();
    await assert.rejects(
      () =>
        studentRulesDb
          .collection("cafes")
          .doc("cafe-student")
          .set(cafeDoc({ openAt: "08:00", closingAt: "17:00" })),
      /PERMISSION_DENIED/,
    );
  });
});