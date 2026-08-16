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

  /// Slices [source] from [startAnchor] to [endAnchor] (or to the end of the
  /// source when omitted), failing with a clear expect message when an anchor
  /// is missing so a broken contract reports which anchor broke instead of
  /// throwing an opaque RangeError. When [length] is given the slice covers
  /// exactly that many characters, clamped to the source length.
  String anchoredSlice(
    String source,
    String startAnchor, {
    String? endAnchor,
    int? length,
    String? what,
  }) {
    final start = source.indexOf(startAnchor);
    expect(
      start,
      isNot(-1),
      reason: '$what: start anchor not found: "$startAnchor"',
    );
    final int end;
    if (length != null) {
      end = start + length > source.length ? source.length : start + length;
    } else if (endAnchor != null) {
      final foundEnd = source.indexOf(endAnchor, start);
      expect(
        foundEnd,
        isNot(-1),
        reason: '$what: end anchor not found: "$endAnchor"',
      );
      end = foundEnd;
    } else {
      end = source.length;
    }
    return source.substring(start, end);
  }

  group('Firestore rules — food disposition foundation', () {
    late String rules;
    setUpAll(() {
      rules = readRepoFile('firestore.rules');
    });

    test('foodDisposition fields are server-protected from all client writes '
        '(§38)', () {
      final protectedFn = anchoredSlice(
        rules,
        'function adminNotModifyingProtectedOrderFields()',
        endAnchor: 'function canonicalOrderStatus(status)',
        what: 'protected order fields',
      );
      expect(protectedFn, contains("!('foodDisposition' in changed)"));
      expect(protectedFn, contains("!('foodDispositionAt' in changed)"));
      expect(protectedFn, contains("!('foodDispositionBy' in changed)"));
      expect(protectedFn, contains("!('foodDispositionNote' in changed)"));
    });

    test('no client create rule exists on /orders (callable-only creation '
        'remains)', () {
      final orderBlock = anchoredSlice(
        rules,
        'match /orders/{docId}',
        endAnchor: 'match /section/{sectionId}',
        what: 'orders block',
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
        anchoredSlice(
          fn,
          'exports.setFoodDisposition',
          endAnchor: 'FUNCTION 5: deleteCloudinaryImage',
          what: 'setFoodDisposition callable',
        ),
        contains('enforceAppCheck: true'),
      );
    });

    test('the controlled disposition list matches AGENTS.md §2', () {
      final listFn = anchoredSlice(
        fn,
        'const FOOD_DISPOSITIONS =',
        endAnchor: '];',
        what: 'FOOD_DISPOSITIONS list',
      );
      final declared = RegExp(
        r'"([A-Z_]+)"',
      ).allMatches(listFn).map((m) => m.group(1)!).toSet();
      expect(
        declared,
        equals(const {
          'UNRESOLVED',
          'RESOLD',
          'DISCOUNTED',
          'DONATED',
          'STAFF_USE',
          'DISPOSED',
          'OTHER',
        }),
        reason:
            'declared FOOD_DISPOSITIONS must equal the Phase H §2 set '
            'exactly — extra or missing entries must fail',
      );
    });

    test('the callable enforces admin-only authorization (§7)', () {
      final callable = anchoredSlice(
        fn,
        'exports.setFoodDisposition = onCall(',
        endAnchor: 'FUNCTION 5: deleteCloudinaryImage',
        what: 'setFoodDisposition admin authorization',
      );
      expect(callable, contains('callerData.role !== "admin"'));
      expect(callable, contains('accountStatus !== "ACTIVE"'));
      expect(callable, contains('callerCafeName'));
      expect(
        callable,
        contains('assertAdminServesOrder(callerCafeName, orderData)'),
        reason:
            'per-cafe scope is enforced through the shared '
            'assertAdminServesOrder helper (§7)',
      );
    });

    test('the callable enforces NO_SHOW-only eligibility and idempotency '
        '(§4, §16)', () {
      final callable = anchoredSlice(
        fn,
        'exports.setFoodDisposition = onCall(',
        endAnchor: 'FUNCTION 5: deleteCloudinaryImage',
        what: 'setFoodDisposition eligibility',
      );
      expect(
        callable,
        contains('"Only no-show orders can have a food disposition."'),
      );
      expect(callable, contains('orderData.foodDisposition === disposition'));
      expect(callable, contains('alreadyRecorded'));
    });

    test('the order update and audit record commit atomically in one '
        'transaction (§15)', () {
      final callable = anchoredSlice(
        fn,
        'exports.setFoodDisposition = onCall(',
        endAnchor: 'FUNCTION 5: deleteCloudinaryImage',
        what: 'setFoodDisposition transaction',
      );
      expect(callable, contains('db.runTransaction'));
      expect(callable, contains('transaction.update(orderRef, {'));
      expect(callable, contains('"FOOD_DISPOSITION"'));
      expect(callable, contains('previousDisposition'));
      expect(callable, contains('newDisposition'));
    });

    test('UNRESOLVED is the default on both no-show paths (§3)', () {
      final sched = anchoredSlice(
        fn,
        'async function processExpiredOrder',
        endAnchor: 'function reliabilityOutcomeFromStatus',
        what: 'scheduled no-show processor',
      );
      expect(sched, contains('foodDisposition: "UNRESOLVED"'));
      expect(
        anchoredSlice(
          fn,
          'async function handleOrderNoShow',
          endAnchor: 'exports.onOrderStatusChanged = onDocumentUpdated(',
          what: 'handleOrderNoShow',
        ),
        contains('foodDisposition: "UNRESOLVED"'),
      );
    });
  });

  group('Student model — disposition privacy (§22)', () {
    test(
      'FoodOrder parses a NO_SHOW order without exposing disposition',
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

        expect(
          order.status,
          OrderStatus.noShow,
          reason: 'history is preserved',
        );
        expect(order.noShowExcused, isFalse);
        // The student-facing model source carries no disposition fields — the
        // cafe's operational record never leaks into the student experience.
        final modelSource = File('lib/models/order.dart').readAsStringSync();
        expect(modelSource, isNot(contains('foodDisposition')));
      },
    );
  });
}
