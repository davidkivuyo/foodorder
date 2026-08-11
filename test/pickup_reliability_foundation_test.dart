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

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/models/pickup_reliability.dart';
import 'package:campusbite/models/user_profile.dart';

/// Phase B.2 — PICKUP RELIABILITY CALCULATION.
///
/// Static guardrail tests (same pattern as no_show_foundation_test.dart)
/// that assert the shipped backend contract survives refactors:
///   * pickupReliability is server-authoritative — students can read their
///     own summary but never write it (rules + model).
///   * Only terminal pickup outcomes (COLLECTED / NO_SHOW) drive updates;
///     cancelled / READY / never-accepted orders never count.
///   * The engine is event-driven, idempotent (reliabilityProcessed marker
///     inside the transaction) and transactional (no full-history scans).
///   * The 10-entry recent window, 70/30 weighted score and status
///     thresholds match the phase contract.
void main() {
  String readRepoFile(String path) => File(path).readAsStringSync();

  group('Firestore rules — pickupReliability is server-authoritative', () {
    late String rules;
    setUpAll(() {
      rules = readRepoFile('firestore.rules');
    });

    test('students can never write pickupReliability (Test 11)', () {
      final studentUpdateFn = rules.substring(
        rules.indexOf('function studentNotModifyingProtectedFields()'),
        rules.indexOf('function validUserCreateRequest()'),
      );
      // Explicit defence-in-depth guard plus the hasOnly allowlist that
      // excludes the nested map entirely.
      expect(studentUpdateFn, contains("!('pickupReliability' in changed)"));
      expect(studentUpdateFn, contains("'fullName', 'email', 'phoneNumber', 'cafeName'"));
      // The favourite-list path is also guarded.
      final favoriteFn = rules.substring(
        rules.indexOf('function validFavoriteMenuUpdate()'),
        rules.indexOf('function validAdminStrikeUpdate()'),
      );
      expect(favoriteFn, contains("!('pickupReliability' in changed)"));
    });

    test('favourite list elements are validated (non-empty strings ≤ 100)',
        () {
      final favoriteListFn = rules.substring(
        rules.indexOf('function validFavoriteMenuList('),
        rules.indexOf('function validFavoriteMenuUpdate()'),
      );
      // Element-level constraints: up to 5 entries, each a non-empty string
      // of at most 100 characters (a food_items document ID), validated per
      // known index because the rules language cannot iterate lists.
      expect(favoriteListFn, contains('list.size() <= 5'));
      expect(favoriteListFn, contains('list[0] is string'));
      expect(favoriteListFn, contains('list[4] is string'));
      expect(favoriteListFn, contains('list[0].size() > 0'));
      expect(favoriteListFn, contains('list[0].size() <= 100'));
      expect(favoriteListFn, contains('list.size() < 1'));
      expect(favoriteListFn, contains('list.size() < 5'));
      // validFavoriteMenuUpdate must delegate to the element validator.
      final updateFn = rules.substring(
        rules.indexOf('function validFavoriteMenuUpdate()'),
        rules.indexOf('function validAdminStrikeUpdate()'),
      );
      expect(
        updateFn,
        contains('validFavoriteMenuList(request.resource.data.favoriteMenu)'),
      );
    });

    test('reliabilityProcessed and reliabilityOutcome are protected order fields',
        () {
      final protectedFn = rules.substring(
        rules.indexOf('function adminNotModifyingProtectedOrderFields()'),
        rules.indexOf('function canonicalOrderStatus(status)'),
      );
      expect(protectedFn, contains("!('reliabilityProcessed' in changed)"));
      // The counted outcome is immutable: clients may not forge or change it.
      expect(protectedFn, contains("!('reliabilityOutcome' in changed)"));
    });

    test('deferral/skip markers are protected order fields', () {
      final protectedFn = rules.substring(
        rules.indexOf('function adminNotModifyingProtectedOrderFields()'),
        rules.indexOf('function canonicalOrderStatus(status)'),
      );
      expect(protectedFn, contains("!('reliabilityPending' in changed)"));
      expect(protectedFn, contains("!('reliabilityPendingSince' in changed)"));
      expect(protectedFn, contains("!('reliabilitySkippedReason' in changed)"));
      expect(protectedFn, contains("!('reliabilitySkippedAt' in changed)"));
    });

    test('user read is owner-or-admin — a student can read their own summary',
        () {
      final userMatch = rules.substring(
        rules.indexOf('match /users/{userId}'),
        rules.indexOf('match /user/{userId}'),
      );
      expect(userMatch, contains('allow read: if isOwner(userId) || isAdmin();'));
    });
  });

  group('Cloud Functions — reliability engine', () {
    late String fn;
    setUpAll(() {
      fn = readRepoFile('functions/index.js');
    });

    test('the engine is event-driven and transactional (no order scans)', () {
      final engineFn = fn.substring(
        fn.indexOf('async function processReliabilityEvent('),
        fn.indexOf('// FUNCTION 2: onOrderStatusChanged'),
      );
      expect(engineFn, contains('db.runTransaction'));
      expect(engineFn, contains('transaction.get(orderRef)'));
      expect(engineFn, contains('transaction.get(userRef)'));
      expect(engineFn, contains('transaction.update(userRef'));
      expect(engineFn, contains('reliabilityProcessed'));
      // The counted outcome is persisted immutably alongside the marker.
      expect(engineFn, contains('reliabilityOutcome: outcome'));
      // No collection-wide order query inside the engine.
      expect(engineFn, isNot(contains('.collection("orders").where')));
    });

    test('idempotency marker prevents double counting (Test 7)', () {
      expect(fn, contains('orderData.reliabilityProcessed === true'));
      expect(fn, contains('e.orderId !== orderId'));
    });

    test('a missing user doc defers the event instead of dropping it', () {
      final engineFn = fn.substring(
        fn.indexOf('async function processReliabilityEvent('),
        fn.indexOf('// FUNCTION 2: onOrderStatusChanged'),
      );
      // The old permanent-drop path (marking the order processed when the
      // user doc is missing) must be gone.
      expect(engineFn, isNot(contains('marking order')));
      // The counting transaction returns a deferral sentinel; the deferral
      // writes its pending marker in its OWN transaction, so the marker
      // survives the retriable throw.
      expect(engineFn, contains('DEFER_RELIABILITY_EVENT'));
      expect(engineFn, contains('deferReliabilityEvent(orderRef)'));
      // The give-up is explicit and auditable (reason + timestamp).
      expect(engineFn, contains('reliabilitySkippedReason'));
      expect(engineFn, contains('MISSING_USER'));
      expect(engineFn, contains('reliabilitySkippedAt'));
      expect(fn, contains('RELIABILITY_MISSING_USER_RETRY_MS'));
    });

    test('the deferral re-reads order + user in a transaction and re-checks '
        'before writing skip metadata', () {
      final deferFn = fn.substring(
        fn.indexOf('async function deferReliabilityEvent('),
        fn.indexOf('// FUNCTION 2: onOrderStatusChanged'),
      );
      // Order + user re-read and the marker writes happen in one
      // transaction, so a concurrent count or restored user doc cannot be
      // overwritten by a stale skip.
      expect(deferFn, contains('db.runTransaction'));
      expect(deferFn, contains('transaction.get(orderRef)'));
      expect(deferFn, contains('db.collection("users").doc(studentId)'));
      // No changes when the event was already counted by a concurrent
      // delivery or the user document now exists.
      expect(deferFn, contains('orderData.reliabilityProcessed === true'));
      expect(deferFn, contains('userSnapshot.exists'));
      expect(deferFn, contains('return "countNow"'));
      // The skip metadata write is inside the transaction, guarded by the
      // re-reads above.
      expect(deferFn, contains('transaction.update(orderRef,'));
      expect(deferFn, contains('reliabilitySkippedReason: "MISSING_USER"'));
      // The retriable 'deferred' contract the reconciler classifies on is
      // preserved for both the pending and the countNow paths, and countNow
      // must never return false (that would drop the race-window event).
      expect(deferFn, contains('result === "defer" || result === "countNow"'));
      expect(deferFn, contains('— deferred'));
    });

    test('successful counting clears stale deferral/skip markers', () {
      final engineFn = fn.substring(
        fn.indexOf('async function processReliabilityEvent('),
        fn.indexOf('// FUNCTION 2: onOrderStatusChanged'),
      );
      expect(engineFn, contains('reliabilityPending: admin.firestore.FieldValue.delete()'));
      expect(engineFn, contains('reliabilitySkippedReason: admin.firestore.FieldValue.delete()'));
    });

    test('the scheduled processor reconciles deferred events (never stranded)',
        () {
      // Cloud Functions redelivers a failed trigger only for a bounded
      // window, so the scheduled processor must also reconcile
      // reliabilityPending orders (count when the user doc appears, give up
      // explicitly after the window) — otherwise an event could be stranded
      // forever.
      expect(fn, contains('async function reconcilePendingReliabilityOrders()'));
      expect(fn, contains('.where("reliabilityPending", "==", true)'));
      expect(fn, contains('reconcilePendingReliabilityOrders()'));
      expect(fn, contains('RELIABILITY_MISSING_USER_RETRY_MS'));
    });

    test('the recent window is capped at 10 (Tests 5 & 12)', () {
      expect(fn, contains('RECENT_PICKUP_WINDOW_SIZE = 10'));
      expect(fn, contains('history.length > RECENT_PICKUP_WINDOW_SIZE'));
    });

    test('the 70/30 weighted score and NEW defaults exist (Tests 13 & 14)',
        () {
      expect(fn, contains('rawCollectionRate * 0.7 + rawRecentCollectionRate * 0.3'));
      // Rounding is applied only to the stored/displayed values, never to the
      // inputs of the weighted score or the status threshold evaluation.
      expect(fn, contains('roundRate(rawCollectionRate)'));
      expect(fn, contains('reliabilityStatusFor(eligibleOrders, rawReliabilityScore)'));
      expect(fn, contains('collectionRate: 100'));
      expect(fn, contains('reliabilityScore: 100'));
      expect(fn, contains('status: "NEW"'));
    });

    test('status thresholds match the phase contract (section 9)', () {
      final statusFn = fn.substring(
        fn.indexOf('function reliabilityStatusFor('),
        fn.indexOf('function recomputeReliability('),
      );
      expect(statusFn, contains('eligibleOrders === 0'));
      expect(statusFn, contains('eligibleOrders <= 2'));
      expect(statusFn, contains('INSUFFICIENT_HISTORY'));
      expect(statusFn, contains('score >= 90'));
      expect(statusFn, contains('EXCELLENT'));
      expect(statusFn, contains('score >= 75'));
      expect(statusFn, contains('GOOD'));
      expect(statusFn, contains('score >= 50'));
      expect(statusFn, contains('NEEDS_IMPROVEMENT'));
      expect(statusFn, contains('score >= 25'));
      expect(statusFn, contains('POOR'));
      expect(statusFn, contains('CRITICAL'));
    });

    test('onOrderStatusChanged processes COLLECTED and NO_SHOW (Tests 2-4)',
        () {
      expect(fn, contains('processReliabilityEvent(event.data.after.ref, "COLLECTED")'));
      expect(fn, contains('processReliabilityEvent(event.data.after.ref, "NO_SHOW")'));
    });

    test('only genuine READY → terminal transitions count (never-READY orders '
        'never affect reliability)', () {
      // A terminal event whose before-status is not "ready" (e.g. an order
      // jumping straight from pending to collected) must never reach the
      // reliability engine — this is the guard the pending→terminal
      // regression tests rely on.
      expect(fn, contains('const beforeStatus ='));
      expect(fn, contains('if (beforeStatus === "ready") {'));
    });

    test('the old strike engine remains removed', () {
      // The notification type-role map still lists STRIKE_ISSUED for legacy
      // notifications, but the engine itself must never issue strikes.
      expect(fn, isNot(contains('automatic_strike')));
      expect(fn, isNot(contains('strikeCount + 1')));
      expect(fn, isNot(contains('STRIKE_ISSUED notification')));
    });
  });

  group('PickupReliabilitySummary model', () {
    test('a missing summary parses to the neutral NEW state (Test 1)', () {
      final summary = PickupReliabilitySummary.fromMap(const {});
      expect(summary.status, PickupReliabilityStatus.newUser);
      expect(summary.eligibleOrders, 0);
      expect(summary.collectionRate, 100);
      expect(summary.reliabilityScore, 100);
      expect(summary.isNewUser, isTrue);
    });

    test('parses a full server-written summary', () {
      final now = DateTime.now();
      final summary = PickupReliabilitySummary.fromMap({
        'eligibleOrders': 10,
        'collectedOrders': 8,
        'noShowOrders': 2,
        'collectionRate': 80.0,
        'recentEligibleOrders': 10,
        'recentCollectedOrders': 6,
        'recentNoShowOrders': 4,
        'recentCollectionRate': 60.0,
        'reliabilityScore': 74.0,
        'status': 'NEEDS_IMPROVEMENT',
        'updatedAt': Timestamp.fromDate(now),
        'recentPickupHistory': [
          {'orderId': 'o1', 'outcome': 'COLLECTED', 'timestamp': Timestamp.fromDate(now)},
          {'orderId': 'o2', 'outcome': 'NO_SHOW', 'timestamp': Timestamp.fromDate(now)},
        ],
      });
      expect(summary.eligibleOrders, 10);
      expect(summary.collectedOrders, 8);
      expect(summary.collectionRate, 80.0);
      expect(summary.status, PickupReliabilityStatus.needsImprovement);
      expect(summary.recentPickupHistory, hasLength(2));
      expect(summary.recentPickupHistory[0].outcome, 'COLLECTED');
    });

    test('history entries with a non-Map<String,dynamic> generic instantiation '
        'are still parsed (normalised, not dropped)', () {
      // Firestore-returned maps can carry a different runtime generic
      // instantiation (e.g. Map<dynamic, dynamic>); the parser must
      // normalise with Map<String, dynamic>.from() instead of strictly
      // filtering by generic type.
      final rawHistory = <Map<dynamic, dynamic>>[
        {'orderId': 'o1', 'outcome': 'COLLECTED'},
        {'orderId': 'o2', 'outcome': 'NO_SHOW'},
      ];
      final summary = PickupReliabilitySummary.fromMap({
        'status': 'NEW',
        'recentPickupHistory': rawHistory,
      });
      expect(summary.recentPickupHistory, hasLength(2));
      expect(summary.recentPickupHistory[0].orderId, 'o1');
      expect(summary.recentPickupHistory[0].outcome, 'COLLECTED');
      expect(summary.recentPickupHistory[1].outcome, 'NO_SHOW');
    });

    test('non-Map history entries are skipped (fail closed)', () {
      final summary = PickupReliabilitySummary.fromMap({
        'status': 'NEW',
        'recentPickupHistory': [
          {'orderId': 'o1', 'outcome': 'COLLECTED'},
          'not-a-map',
          42,
        ],
      });
      expect(summary.recentPickupHistory, hasLength(1));
      expect(summary.recentPickupHistory[0].orderId, 'o1');
    });

    test('status string round-trips', () {
      expect(
        PickupReliabilityStatus.fromString('EXCELLENT'),
        PickupReliabilityStatus.excellent,
      );
      expect(
        PickupReliabilityStatus.excellent.toShortString(),
        'EXCELLENT',
      );
      expect(
        PickupReliabilityStatus.fromString('INSUFFICIENT_HISTORY'),
        PickupReliabilityStatus.insufficientHistory,
      );
    });
  });

  group('UserProfile — reliability exposure', () {
    test('parses pickupReliability from the user document', () {
      final profile = UserProfile.fromFirestore('uid1', {
        'fullName': 'Test Student',
        'email': 't@test.com',
        'role': 'student',
        'pickupReliability': {
          'eligibleOrders': 3,
          'collectedOrders': 3,
          'noShowOrders': 0,
          'collectionRate': 100.0,
          'reliabilityScore': 100.0,
          'status': 'EXCELLENT',
        },
      });
      expect(profile.pickupReliability, isNotNull);
      expect(profile.pickupReliability!.status, PickupReliabilityStatus.excellent);
      expect(profile.pickupReliability!.eligibleOrders, 3);
    });

    test('a user document without the summary yields null (treated as NEW)',
        () {
      final profile = UserProfile.fromFirestore('uid2', {
        'fullName': 'New Student',
        'email': 'n@test.com',
      });
      expect(profile.pickupReliability, isNull);
    });

    test('toFirestoreCreate never includes pickupReliability', () {
      final map = const UserProfile(
        fullName: 'Test',
        email: 't@test.com',
      ).toFirestoreCreate();
      expect(map.containsKey('pickupReliability'), isFalse);
    });
  });

  group('Emulator integration coverage — reliability engine', () {
    test('the Firestore-emulator integration suite exists and is runnable', () {
      final integration =
          readRepoFile('functions/test/pickup_reliability_integration.test.js');
      expect(integration, contains('initializeTestEnvironment'));
      expect(integration, contains('onOrderStatusChanged.run'));
      expect(integration, contains('Test 8 — concurrent'));
      expect(integration, contains('(Test 11)'));
      expect(integration, contains('(Tests 1, 2, 3, 4, 14)'));
      expect(integration, contains('(Tests 5, 6, 12)'));
      expect(integration, contains('(Tests 7, 8)'));
      expect(integration, contains('(Tests 9, 10)'));
      expect(integration, contains('(Test 13)'));
    });

    test('the integration suite is wired into the npm scripts', () {
      final packageJson = readRepoFile('functions/package.json');
      expect(packageJson, contains('test:reliability:integration'));
      expect(packageJson, contains('emulators:exec --only firestore'));
    });
  });
}
