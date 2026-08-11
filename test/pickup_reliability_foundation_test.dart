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

    test('reliabilityProcessed is a protected order field', () {
      final protectedFn = rules.substring(
        rules.indexOf('function adminNotModifyingProtectedOrderFields()'),
        rules.indexOf('function canonicalOrderStatus(status)'),
      );
      expect(protectedFn, contains("!('reliabilityProcessed' in changed)"));
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
      // No collection-wide order query inside the engine.
      expect(engineFn, isNot(contains('.collection("orders").where')));
    });

    test('idempotency marker prevents double counting (Test 7)', () {
      expect(fn, contains('orderData.reliabilityProcessed === true'));
      expect(fn, contains('e.orderId !== orderId'));
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
