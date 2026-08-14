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

/// Phase A — NO-SHOW FOUNDATION.
///
/// Static guardrail tests (same pattern as auth_hardening_test.dart) that
/// assert the shipped backend contract survives refactors:
///   * NO_SHOW is a canonical order state and COLLECTED stays the successful
///     terminal state (mutually exclusive, enforced server-side).
///   * readyAt / pickupDeadline / collectedAt / expiredAt are authoritative
///     server-written timestamps; students cannot forge order status or
///     timestamps (order updates are admin-gated).
///   * READY -> NO_SHOW is idempotent, collected always wins, and the
///     deadline must actually have passed inside the transaction.
///   * The old strike-based suspension is gone from the customer path.
void main() {
  String readRepoFile(String path) => File(path).readAsStringSync();

  group('Firestore rules — no-show foundation', () {
    late String rules;
    setUpAll(() {
      rules = readRepoFile('firestore.rules');
    });

    test('order updates are admin-gated — students cannot forge NO_SHOW or '
        'timestamps (Tests 8 & 9)', () {
      final orderBlock = rules.substring(
        rules.indexOf('match /orders/{docId}'),
        rules.indexOf('match /section/{sectionId}'),
      );
      // Students may only create orders (status pending) and read their own;
      // every update requires the admin gate.
      expect(orderBlock, contains('allow update: if isAdmin()'));
      expect(orderBlock, isNot(contains('allow update: if isAuth()')));
    });

    test('ready -> collected enforces pickupGracePeriodNotExpired cutoff (Tests 4, 5, 14)', () {
      final transitionFn = rules.substring(
        rules.indexOf('function validOrderStatusTransition()'),
        rules.indexOf('// ── User validation ─'),
      );
      // no_show is a first-class allowed status.
      expect(
        transitionFn,
        contains("'ready', 'collected', 'no_show'"),
      );
      // Terminal transition ready -> collected requires pickupGracePeriodNotExpired.
      expect(transitionFn, contains("(before == 'ready'"));
      expect(
        transitionFn,
        contains("after == 'collected' && pickupGracePeriodNotExpired()"),
      );
      expect(rules, contains('function pickupGracePeriodNotExpired()'));
      expect(rules, contains('duration.value(5, \'m\')'));
    });

    test('collectedAt is server-protected from admin writes', () {
      final protectedFn = rules.substring(
        rules.indexOf('function adminNotModifyingProtectedOrderFields()'),
        rules.indexOf('function canonicalOrderStatus(status)'),
      );
      expect(protectedFn, contains("!('collectedAt' in changed)"));
      // The no-show state fields remain protected too.
      expect(protectedFn, contains("!('noShowProcessed' in changed)"));
      expect(protectedFn, contains("!('noShowAt' in changed)"));
      expect(protectedFn, contains("!('expiredAt' in changed)"));
    });

    test('strike-count suspension is removed from the student order path '
        '(STEP 2)', () {
      // The old isStudentSuspended() helper only gated the deleted
      // validOrderCreateRequest(); with order creation moved to the
      // placeOrder callable it no longer exists. Suspension enforcement now
      // lives server-side in the callable (reads the user's accountStatus),
      // and the deleted strike engine's `strikeCount >= 2` block must not
      // come back in the order path.
      expect(rules, isNot(contains('function isStudentSuspended()')));
    });

    test('order create is exclusively server-authoritative — no client '
        'create rule (Phase E)', () {
      // The direct-create rule (and its validOrderCreateRequest() helper)
      // was revoked when order creation moved to the placeOrder callable:
      // a client-side create could bypass the Phase E active-order limit
      // and forge server-owned fields (readyAt, pickupDeadline, collectedAt,
      // noShowAt, ...). Only the callable (Admin SDK) may create orders.
      expect(rules, isNot(contains('function validOrderCreateRequest()')));
      final orderBlock = rules.substring(
        rules.indexOf('match /orders/{docId}'),
        rules.indexOf('match /section/{sectionId}'),
      );
      expect(orderBlock, isNot(contains('allow create')));
    });
  });

  group('Cloud Functions — no-show transition mechanism', () {
    late String fn;
    setUpAll(() {
      fn = readRepoFile('functions/index.js');
    });

    test('processExpiredOrder verifies eligibility and grace period cutoff '
        'inside the transaction (Tests 4, 5, 6, 7)', () {
      final expiryFn = fn.substring(
        fn.indexOf('async function processExpiredOrder('),
        fn.indexOf('exports.processExpiredPickups'),
      );
      // Order must be READY, ACTIVE and not already processed.
      expect(expiryFn, contains('orderData.status !== "ready"'));
      expect(expiryFn, contains('orderData.deadlineStatus !== "ACTIVE"'));
      expect(expiryFn, contains('orderData.noShowProcessed === true'));
      // A deadline must exist (Timestamp) and pickupDeadline + gracePeriod must have passed.
      expect(
        expiryFn,
        contains('pickupDeadline instanceof admin.firestore.Timestamp'),
      );
      expect(expiryFn, contains('DEFAULT_PICKUP_GRACE_PERIOD_MINUTES'));
      expect(expiryFn, contains('now.toMillis() < noShowEligibleAtMs'));
      // The transition writes exactly the no-show state + timestamp.
      expect(expiryFn, contains('status: "no_show"'));
      expect(
        expiryFn,
        contains('expiredAt: admin.firestore.FieldValue.serverTimestamp()'),
      );
      expect(expiryFn, contains('action: "automatic_no_show"'));
    });

    test('the scheduled query runs every 1 minute and targets expired grace period orders '
        '(Test 6 — collected excluded)', () {
      expect(fn, contains('.schedule("every 1 minutes")'));
      expect(fn, contains('.where("status", "==", "ready")'));
      expect(fn, contains('.where("deadlineStatus", "==", "ACTIVE")'));
      expect(fn, contains('.where("pickupDeadline", "<=", graceExpiryThreshold)'));
    });

    test('the order is re-read inside a transaction before deciding '
        '(Test 10 — concurrent collection wins)', () {
      expect(
        fn,
        contains('const freshSnapshot = await transaction.get(orderSnapshot.ref);'),
      );
    });

    test('onOrderStatusChanged records authoritative readyAt + pickupDeadline '
        'on READY (Tests 1 & 2)', () {
      final statusFn = fn.substring(
        fn.indexOf('exports.onOrderStatusChanged'),
        fn.indexOf('exports.onNewOrder'),
      );
      expect(statusFn, contains('readyAt: now'));
      expect(statusFn, contains('pickupDeadline: deadline'));
      expect(statusFn, contains('deadlineStatus: "ACTIVE"'));
      expect(statusFn, contains('PICKUP_WINDOW_MINUTES'));
    });

    test('onOrderStatusChanged records collectedAt on COLLECTED (Test 3)', () {
      final statusFn = fn.substring(
        fn.indexOf('exports.onOrderStatusChanged'),
        fn.indexOf('exports.onNewOrder'),
      );
      expect(statusFn, contains('status === "collected"'));
      expect(
        statusFn,
        contains('collectedAt: admin.firestore.Timestamp.now()'),
      );
    });

    test('the terminal timestamp is persisted before reliability processing '
        'so history uses the authoritative time', () {
      final statusFn = fn.substring(
        fn.indexOf('exports.onOrderStatusChanged'),
        fn.indexOf('exports.onNewOrder'),
      );
      // COLLECTED: the collectedAt write must precede the reliability call.
      final collectedBranch = statusFn.substring(
        statusFn.indexOf('status === "collected"'),
        statusFn.indexOf('status === "no_show"'),
      );
      final collectedWrite = collectedBranch.indexOf(
        'collectedAt: admin.firestore.Timestamp.now()',
      );
      final collectedReliability = collectedBranch.indexOf(
        'processReliabilityEvent(event.data.after.ref, "COLLECTED")',
      );
      expect(collectedWrite, greaterThan(-1));
      expect(collectedReliability, greaterThan(collectedWrite));
      // NO_SHOW: the expiredAt write must precede the reliability call.
      final noShowBranch = statusFn.substring(
        statusFn.indexOf('status === "no_show"'),
      );
      final expiredWrite = noShowBranch.indexOf(
        'expiredAt: admin.firestore.Timestamp.now()',
      );
      final noShowReliability = noShowBranch.indexOf(
        'processReliabilityEvent(event.data.after.ref, "NO_SHOW")',
      );
      expect(expiredWrite, greaterThan(-1));
      expect(noShowReliability, greaterThan(expiredWrite));
      // A fresh-read guard stops a redelivered event from re-stamping the
      // persisted terminal timestamp.
      expect(statusFn, contains('freshSnapshot.data().collectedAt == null'));
      expect(statusFn, contains('freshSnapshot.data().expiredAt == null'));
    });

    test('onOrderStatusChanged keeps manually marked NO_SHOW orders '
        'self-consistent', () {
      final statusFn = fn.substring(
        fn.indexOf('exports.onOrderStatusChanged'),
        fn.indexOf('exports.onNewOrder'),
      );
      expect(statusFn, contains('status === "no_show"'));
      expect(statusFn, contains('noShowProcessed: true'));
      expect(
        statusFn,
        contains('expiredAt: admin.firestore.Timestamp.now()'),
      );
    });

    test('ORDER_NO_SHOW notifications are deduplicated by eventId', () {
      expect(fn, contains('notificationEventId("ORDER_NO_SHOW", orderId)'));
      // Atomic create on the deterministic doc ID — a redelivered event can
      // never overwrite an existing notification.
      expect(fn, contains('await ref.create(payload)'));
    });
  });

  group('CartService — strike-based restriction removed', () {
    test('isAccountSuspended keeps only the accountStatus gate', () {
      final cart = readRepoFile('lib/services/cart_service.dart');
      expect(cart, isNot(contains('strikeCount >= 2')));
      expect(cart, contains("return accountStatus == 'SUSPENDED';"));
    });
  });

  group('Firestore indexes — no-show processor query', () {
    test('composite index exists for status + deadlineStatus + pickupDeadline',
        () {
      final indexes = readRepoFile('firestore.indexes.json');
      expect(indexes, contains('"fieldPath": "status", "order": "ASCENDING"'));
      expect(
        indexes,
        contains('"fieldPath": "deadlineStatus", "order": "ASCENDING"'),
      );
      expect(
        indexes,
        contains('"fieldPath": "pickupDeadline", "order": "ASCENDING"'),
      );
    });
  });

  group('Emulator integration coverage — no-show lifecycle', () {
    test('the Firestore-emulator integration suite exists and is runnable', () {
      final integration =
          readRepoFile('functions/test/no_show_integration.test.js');
      // Exercises the real rules engine against a live emulator, covering
      // READY deadline creation, collection, valid/premature expiry,
      // idempotency, student write denial and collection-wins concurrency.
      expect(integration, contains('initializeTestEnvironment'));
      expect(integration, contains('processExpiredPickups.run'));
      expect(integration, contains('onOrderStatusChanged.run'));
      expect(integration, contains('collection wins'));
      expect(integration, contains('concurrent collect race'));
    });

    test('the integration suite is wired into the npm scripts with the '
        'Firestore emulator', () {
      final packageJson = readRepoFile('functions/package.json');
      expect(packageJson, contains('test:no-show:integration'));
      expect(packageJson, contains('emulators:exec --only firestore'));
      // The rules engine is exercised by loading the real firestore.rules.
      expect(packageJson, contains('@firebase/rules-unit-testing'));
      final firebaseJson = readRepoFile('firebase.json');
      expect(firebaseJson, contains('"emulators"'));
      expect(firebaseJson, contains('"firestore"'));
      // The suite connects to the emulator at localhost:8080 — the config
      // must stay in sync or the integration run fails to connect.
      expect(firebaseJson, contains('"port": 8080'));
    });
  });

  group('FoodOrder — no-show & collection timestamps', () {
    test('parses collectedAt and expiredAt from Firestore', () async {
      final now = DateTime.now();
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('orders').doc('CB-1');
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
        'status': 'collected',
        'createdAt': Timestamp.fromDate(now),
        'readyAt': Timestamp.fromDate(now.subtract(const Duration(minutes: 30))),
        'pickupDeadline': Timestamp.fromDate(
          now.subtract(const Duration(minutes: 10)),
        ),
        'collectedAt': Timestamp.fromDate(
          now.subtract(const Duration(minutes: 9)),
        ),
        'expiredAt': null,
        'noShowProcessed': false,
        'deadlineStatus': 'COLLECTED',
        'pickupWindowMinutes': 20,
      });

      final snapshot = await ref.get();
      final order = FoodOrder.fromFirestore(snapshot);

      expect(order.status, OrderStatus.collected);
      expect(order.readyAt, isNotNull);
      expect(order.pickupDeadline, isNotNull);
      expect(order.collectedAt, isNotNull);
      expect(order.expiredAt, isNull);
      expect(order.noShowProcessed, isFalse);
      expect(order.deadlineStatus, DeadlineStatus.collected);
    });

    test('parses a NO_SHOW order with expiredAt and no collectedAt', () async {
      final now = DateTime.now();
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('orders').doc('CB-2');
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
        'readyAt': Timestamp.fromDate(now.subtract(const Duration(minutes: 40))),
        'pickupDeadline': Timestamp.fromDate(
          now.subtract(const Duration(minutes: 20)),
        ),
        'collectedAt': null,
        'expiredAt': Timestamp.fromDate(
          now.subtract(const Duration(minutes: 20)),
        ),
        'noShowAt': Timestamp.fromDate(
          now.subtract(const Duration(minutes: 20)),
        ),
        'noShowProcessed': true,
        'deadlineStatus': 'EXPIRED',
        'pickupWindowMinutes': 20,
      });

      final snapshot = await ref.get();
      final order = FoodOrder.fromFirestore(snapshot);

      expect(order.status, OrderStatus.noShow);
      expect(order.expiredAt, isNotNull);
      expect(order.noShowAt, isNotNull);
      expect(order.collectedAt, isNull);
      expect(order.noShowProcessed, isTrue);
      expect(order.deadlineStatus, DeadlineStatus.expired);
    });

    test('NO_SHOW is the canonical serialized status', () {
      expect(OrderStatus.noShow.toShortString(), 'no_show');
      expect(OrderStatus.fromString('no_show'), OrderStatus.noShow);
    });
  });
}
