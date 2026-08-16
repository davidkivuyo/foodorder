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
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/models/order.dart';

/// Phase H — CAFE FOOD WASTE MANAGEMENT.
///
/// Static guardrail tests (same pattern as no_show_foundation_test.dart) that
/// assert the shipped backend contract survives refactors:
///   * foodDisposition* fields are protected from ALL client writes — only
///     the setFoodDisposition callable (Admin SDK) may write them (§38).
///   * The setFoodDisposition callable exists and enforces the controlled
///     disposition list, admin-only authorization, NO_SHOW eligibility,
///     atomic order+audit commit, and idempotency (§7, §15-§17).
///   * UNRESOLVED is the default state on the no-show paths (§3).
///   * The student FoodOrder model does not expose disposition fields —
///     students never see private cafe waste details (§22).
void main() {
  String readRepoFile(String path) => File(path).readAsStringSync();

  group('Firestore rules — food disposition foundation', () {
    late String rules;
    setUpAll(() {
      rules = readRepoFile('firestore.rules');
    });

    test('foodDisposition fields are server-protected from all client writes '
        '(§38)', () {
      final protectedFn = rules.substring(
        rules.indexOf('function adminNotModifyingProtectedOrderFields()'),
        rules.indexOf('function canonicalOrderStatus(status)'),
      );
      expect(protectedFn, contains("!('foodDisposition' in changed)"));
      expect(protectedFn, contains("!('foodDispositionAt' in changed)"));
      expect(protectedFn, contains("!('foodDispositionBy' in changed)"));
      expect(protectedFn, contains("!('foodDispositionNote' in changed)"));
    });

    test('no client create rule exists on /orders (callable-only creation '
        'remains)', () {
      final orderBlock = rules.substring(
        rules.indexOf('match /orders/{docId}'),
        rules.indexOf('match /section/{sectionId}'),
      );
      expect(orderBlock, isNot(contains('allow create')));
    });
  });

  group('Cloud Functions — setFoodDisposition contract', () {
    late String fn;
    setUpAll(() {
      fn = readRepoFile('functions/index.js');
    });

    test('the setFoodDisposition callable exists with admin + App Check', () {
      expect(fn, contains('exports.setFoodDisposition = onCall('));
      expect(
        fn.substring(fn.indexOf('exports.setFoodDisposition'), fn.length),
        contains('enforceAppCheck: true'),
      );
    });

    test('the controlled disposition list matches AGENTS.md §2', () {
      final listFn = fn.substring(
        fn.indexOf('const FOOD_DISPOSITIONS ='),
        fn.indexOf('const FOOD_DISPOSITIONS =') + 400,
      );
      for (final d in [
        'UNRESOLVED',
        'RESOLD',
        'DISCOUNTED',
        'DONATED',
        'STAFF_USE',
        'DISPOSED',
        'OTHER',
      ]) {
        expect(listFn, contains('"$d"'));
      }
    });

    test('the callable enforces admin-only authorization (§7)', () {
      final callable = fn.substring(
        fn.indexOf('exports.setFoodDisposition = onCall('),
        fn.indexOf('FUNCTION 5: deleteCloudinaryImage'),
      );
      expect(callable, contains('callerData.role !== "admin"'));
      expect(callable, contains('accountStatus !== "ACTIVE"'));
      expect(callable, contains('not authorized to manage orders'));
      expect(callable, contains('callerCafeName'));
    });

    test('the callable enforces NO_SHOW-only eligibility and idempotency '
        '(§4, §16)', () {
      final callable = fn.substring(
        fn.indexOf('exports.setFoodDisposition = onCall('),
        fn.indexOf('FUNCTION 5: deleteCloudinaryImage'),
      );
      expect(callable, contains('"Only no-show orders can have a food disposition."'));
      expect(callable, contains('orderData.foodDisposition === disposition'));
      expect(callable, contains('alreadyRecorded'));
    });

    test('the order update and audit record commit atomically in one '
        'transaction (§15)', () {
      final callable = fn.substring(
        fn.indexOf('exports.setFoodDisposition = onCall('),
        fn.indexOf('FUNCTION 5: deleteCloudinaryImage'),
      );
      expect(callable, contains('db.runTransaction'));
      expect(callable, contains('transaction.update(orderRef, {'));
      expect(callable, contains('"FOOD_DISPOSITION"'));
      expect(callable, contains('previousDisposition'));
      expect(callable, contains('newDisposition'));
    });

    test('UNRESOLVED is the default on both no-show paths (§3)', () {
      final sched = fn.substring(
        fn.indexOf('async function processExpiredOrder'),
        fn.indexOf('function reliabilityOutcomeFromStatus'),
      );
      expect(sched, contains('foodDisposition: "UNRESOLVED"'));
      expect(
        fn.substring(
          fn.indexOf('async function handleOrderNoShow'),
          fn.indexOf('exports.onOrderStatusChanged = onDocumentUpdated('),
        ),
        contains('foodDisposition: "UNRESOLVED"'),
      );
    });
  });

  group('Student model — disposition privacy (§22)', () {
    test('FoodOrder parses a NO_SHOW order without exposing disposition',
        () async {
      final now = DateTime.now();
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('orders').doc('CB-disposition-1');
      await ref.set({
        'studentId': 'user_1',
        'userName': 'Test Student',
        'items': [
          {
            'foodItemId': 'food_1',
            'title': 'Rice & Beans',
            'price': 3000.0,
            'quantity': 1,
            'image': '',
            'selectedCafe': 'Cafe A',
          },
        ],
        'price': 3000.0,
        'status': 'no_show',
        'createdAt': Timestamp.fromDate(now),
        'noShowAt': Timestamp.fromDate(now),
        'expiredAt': Timestamp.fromDate(now),
        // The backend stores the disposition; the student model must ignore it.
        'foodDisposition': 'DONATED',
        'foodDispositionAt': Timestamp.fromDate(now),
        'foodDispositionNote': 'Donated to campus support staff.',
        'deadlineStatus': 'EXPIRED',
        'pickupWindowMinutes': 20,
      });

      final snapshot = await ref.get();
      final order = FoodOrder.fromFirestore(snapshot);

      expect(order.status, OrderStatus.noShow, reason: 'history is preserved');
      expect(order.noShowExcused, isFalse);
      // The student-facing model source carries no disposition fields — the
      // cafe's operational record never leaks into the student experience.
      final modelSource = File('lib/models/order.dart').readAsStringSync();
      expect(modelSource, isNot(contains('foodDisposition')));
    });
  });
}
