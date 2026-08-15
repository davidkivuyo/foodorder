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
import 'package:campusbite/services/order_cancellation_service.dart';
import 'package:campusbite/viewmodels/orders_view_model.dart';

/// [OrderCancellationService] that always returns a fixed failure result, so
/// the failed/offline cancellation contract (service → ViewModel → UI) can be
/// tested without touching Firebase Functions.
class _FixedCancellationService extends OrderCancellationService {
  _FixedCancellationService(this.failure);

  final OrderCancellationFailure failure;

  @override
  Future<OrderCancellationResult> cancelOrder(
    String orderId, {
    String? reason,
  }) async {
    return (failure: failure);
  }
}

/// Phase B — ORDER CANCELLATION & 2-MINUTE WINDOW.
///
/// Static guardrail tests (same pattern as no_show_foundation_test.dart) that
/// assert the shipped backend contract survives refactors:
///   * CANCELLED is a canonical terminal order state; no rule-allowed
///     transition may leave it, and only the cancelOrder callable may enter it.
///   * The 2-minute cancellation window is server-authoritative: the
///     acceptance rule compares request.time against the server-written
///     cancellationDeadline, and the onNewOrder trigger corrects the deadline.
///   * Students may cancel only their own pending order via the callable;
///     order updates stay admin-gated (no student update path).
///   * CANCELLED orders never become NO_SHOW (the expiry processor only
///     queries status == 'ready') and never affect reliability.
void main() {
  String readRepoFile(String path) => File(path).readAsStringSync();

  group('Firestore rules — cancellation foundation', () {
    late String rules;
    setUpAll(() {
      rules = readRepoFile('firestore.rules');
    });

    test('CANCELLED is a canonical terminal status with no exit transition '
        '(Tests 8-13, 36)', () {
      final transitionFn = rules.substring(
        rules.indexOf('function validOrderStatusTransition()'),
        rules.indexOf('// ── User validation ─'),
      );
      expect(transitionFn, contains("'cancelled'"));
      // There is deliberately no rule-allowed transition INTO cancelled —
      // only the cancelOrder callable (Admin SDK) may enter it.
      expect(transitionFn, isNot(contains("after == 'cancelled'")));
      // And no transition OUT of cancelled: CANCELLED is terminal.
      expect(transitionFn, isNot(contains("before == 'cancelled'")));
    });

    test('admin cannot accept a pending order before the cancellation window '
        'passes (Tests 5 & 6)', () {
      final transitionFn = rules.substring(
        rules.indexOf('function validOrderStatusTransition()'),
        rules.indexOf('// ── User validation ─'),
      );
      // The acceptance branch must consult the server-authoritative deadline.
      expect(transitionFn, contains('cancellationWindowPassed()'));
      expect(transitionFn, contains("after == 'accepted'"));
      // The window is enforced server-side with request.time, never the
      // student's device clock.
      final windowFn = rules.substring(
        rules.indexOf('function cancellationWindowPassed()'),
        rules.indexOf('function validOrderStatusTransition()'),
      );
      expect(windowFn, contains('request.time'));
      expect(windowFn, contains('cancellationDeadline'));
      // Legacy orders (pre-Phase-B, no deadline) remain acceptable ONLY
      // once they have genuinely aged past the 2-minute window — a freshly
      // placed order without a deadline must never be accepted instantly.
      expect(windowFn, contains("('cancellationDeadline' in resource.data)"));
      expect(windowFn, contains("'createdAt' in resource.data"));
      expect(windowFn, contains('duration.value(2, \'m\')'));
    });

    test('cancellation metadata fields are server-written and protected '
        '(Tests 16 & 26)', () {
      final protectedFn = rules.substring(
        rules.indexOf('function adminNotModifyingProtectedOrderFields()'),
        rules.indexOf('function canonicalOrderStatus(status)'),
      );
      expect(protectedFn, contains("!('cancelledAt' in changed)"));
      expect(protectedFn, contains("!('cancelledBy' in changed)"));
      expect(protectedFn, contains("!('cancellationReason' in changed)"));
      expect(protectedFn, contains("!('cancellationDeadline' in changed)"));
    });

    test('order create is exclusively server-authoritative - no client '
        'cancellation deadline can be supplied (Test 1)', () {
      // The direct-create rule was revoked (Phase E - creation happens only
      // through the placeOrder callable), so a client can never write an
      // order with any cancellation metadata: no forged cancelledAt,
      // cancelledBy, cancellationReason or cancellationDeadline (the
      // authoritative createdAt + 2 min value is written by the onNewOrder
      // trigger) can reach the document.
      expect(rules, isNot(contains('function validOrderCreateRequest()')));
      final orderBlock = rules.substring(
        rules.indexOf('match /orders/{docId}'),
        rules.indexOf('match /section/{sectionId}'),
      );
      expect(orderBlock, isNot(contains('allow create')));
    });

    test('orders stay admin-gated for updates — no student cancellation write '
        'path (Test 15)', () {
      final orderBlock = rules.substring(
        rules.indexOf('match /orders/{docId}'),
        rules.indexOf('match /section/{sectionId}'),
      );
      expect(orderBlock, contains('allow update: if adminServesOrder()'));
      expect(orderBlock, isNot(contains('allow update: if isAuth()')));
    });
  });

  group('Cloud Functions — cancellation mechanism', () {
    late String fn;
    setUpAll(() {
      fn = readRepoFile('functions/index.js');
    });

    test('cancelOrder callable enforces ownership, pending status and the '
        'authoritative deadline inside a transaction (Tests 2-4, 7, 8-12, 15)',
        () {
      final cancelFn = fn.substring(
        fn.indexOf('function validateCancelRequest('),
        fn.indexOf('// ── Order foodIds backfill ─'),
      );
      expect(cancelFn, contains('exports.cancelOrder = onCall('));
      // Ownership: only the order's student may cancel.
      expect(cancelFn, contains('orderData.studentId !== uid'));
      // Only a pending order is cancellable.
      expect(cancelFn, contains('orderData.status !== "pending"'));
      // Server-authoritative deadline, never the client clock: the window is
      // always derived from the validated server-resolved createdAt, and the
      // persisted cancellationDeadline is never trusted for the comparison.
      expect(
        cancelFn,
        contains('createdAt instanceof admin.firestore.Timestamp'),
      );
      expect(
        cancelFn,
        contains('createdAt.seconds + CANCELLATION_WINDOW_MINUTES * 60'),
      );
      expect(cancelFn, contains('now.toMillis() >= cancellationDeadline'));
      // Atomic transition inside a transaction.
      expect(cancelFn, contains('db.runTransaction'));
      // Terminal transition + audit metadata.
      expect(cancelFn, contains('status: "cancelled"'));
      expect(cancelFn, contains('cancelledAt'));
      expect(cancelFn, contains('cancelledBy: uid'));
      expect(cancelFn, contains('cancellationReason'));
      // Preset reasons are bounded.
      expect(cancelFn, contains('reason.length > 200'));
    });

    test('onNewOrder writes the authoritative cancellationDeadline from the '
        'server createdAt (Test 5 — server-authoritative)', () {
      final newOrderFn = fn.substring(
        fn.indexOf('exports.onNewOrder'),
        fn.indexOf('exports.onNewNotification'),
      );
      expect(newOrderFn, contains('CANCELLATION_WINDOW_MINUTES'));
      expect(
        newOrderFn,
        contains('orderData.createdAt.seconds + CANCELLATION_WINDOW_MINUTES * 60'),
      );
      expect(newOrderFn, contains('cancellationDeadline: authoritativeDeadline'));
    });

    test('the scheduled no-show processor can never flip a cancelled order '
        '(Test 13)', () {
      // The processor only queries status == 'ready' — cancelled orders are
      // structurally excluded from the query.
      expect(fn, contains('.where("status", "==", "ready")'));
      final expiryFn = fn.substring(
        fn.indexOf('async function processExpiredOrder('),
        fn.indexOf('exports.processExpiredPickups'),
      );
      expect(expiryFn, contains('orderData.status !== "ready"'));
      expect(expiryFn, isNot(contains('"cancelled"')));
    });

    test('ORDER_CANCELLED notifications are routed to students and '
        'deduplicated (Test 19)', () {
      expect(
        fn,
        contains('notificationEventId("ORDER_CANCELLED", orderId)'),
      );
      // Student-only routing in the push allowlist.
      expect(fn, contains('ORDER_CANCELLED: ["student"]'));
    });

    test('foodIds backfill is transactional and never clobbers existing values',
        () {
      final backfillFn = fn.substring(
        fn.indexOf('async function backfillOrderFoodIds('),
        fn.indexOf('async function normalizeOrderPricing('),
      );
      // The presence check and the write happen atomically in one
      // transaction with a fresh re-read of the order.
      expect(backfillFn, contains('db.runTransaction'));
      expect(backfillFn, contains('transaction.get(orderRef)'));
      expect(backfillFn, contains('transaction.update(orderRef'));
      // ANY existing foodIds value — populated, empty, or malformed —
      // aborts the backfill; the field is never overwritten or
      // reinterpreted.
      expect(backfillFn, contains('data.foodIds !== undefined'));
      // The check must not trust the caller-supplied snapshot's foodIds.
      expect(backfillFn, isNot(contains('orderData.foodIds')));
    });

    test('normalizeOrderPricing holds the order instead of falling back to '
        'client prices, and validates before persisting', () {
      final pricingFn = fn.substring(
        fn.indexOf('async function resolveLineItemPrice('),
        fn.indexOf('// PHASE B.2 — PICKUP RELIABILITY ENGINE'),
      );
      // Missing food doc or failed lookup → hold (retriable throw).
      expect(pricingFn, contains('throw new Error('));
      expect(pricingFn, contains('!snap.exists'));
      expect(pricingFn, contains('lookup failed — holding order'));
      // The resolved menu price must be finite and the quantity a positive
      // integer before the line contributes to the total.
      expect(pricingFn, contains('Number.isFinite(unitPrice)'));
      expect(pricingFn, contains('Number.isInteger(quantity)'));
      expect(pricingFn, contains('quantity <= 0'));
      // No fallback to the client-supplied price anywhere.
      expect(
        pricingFn,
        isNot(contains('typeof item.price === "number"')),
      );
    });
  });

  group('OrderCancellationService — client contract', () {
    test('exposes the 2-minute window constant matching the backend', () {
      final service = readRepoFile('lib/services/order_cancellation_service.dart');
      expect(service, contains('static const int windowMinutes = 2;'));
      // No user-facing strings in the service — failures are stable enums.
      expect(service, isNot(contains("return 'Cancellation window")));
    });

    test('backend and client agree on the window length', () {
      final fn = readRepoFile('functions/index.js');
      final service =
          readRepoFile('lib/services/order_cancellation_service.dart');
      expect(fn, contains('const CANCELLATION_WINDOW_MINUTES = 2;'));
      expect(service, contains('windowMinutes = 2;'));
    });

    test('an offline cancellation request yields networkError — never a '
        'success result', () async {
      final service =
          _FixedCancellationService(OrderCancellationFailure.networkError);
      final result = await service.cancelOrder('CB-offline-1');
      // The UI's success snackbar is gated on failure == null, so a failed
      // request can never report "cancelled successfully".
      expect(result.failure, OrderCancellationFailure.networkError);
      expect(result.failure, isNotNull);
    });

    test('a callable-rejected cancellation maps to the stable failure value',
        () async {
      final service = _FixedCancellationService(
        OrderCancellationFailure.failedPrecondition,
      );
      final result = await service.cancelOrder('CB-window-1', reason: 'Other');
      expect(result.failure, OrderCancellationFailure.failedPrecondition);
      expect(result.failure, isNotNull);
    });

    test('the ViewModel propagates cancellation failures so the UI can only '
        'render the error path', () async {
      final service =
          _FixedCancellationService(OrderCancellationFailure.networkError);
      final vm = OrdersViewModel(cancellationService: service);
      final result = await vm.cancelOrder('CB-offline-2', reason: 'Other');
      // Failure is propagated unchanged; a failed/offline request never
      // yields the null-failure "success" result the screen's success
      // snackbar is gated on.
      expect(result.failure, OrderCancellationFailure.networkError);
      expect(result.failure, isNotNull);
      // The per-order in-flight state is cleared even on failure.
      expect(vm.isCancelling('CB-offline-2'), isFalse);
    });

    test('the orders screen only reports cancellation success when the '
        'result carries no failure', () {
      final screen = readRepoFile('lib/screens/order_screen.dart');
      // The success snackbar text is gated on failure == null…
      expect(screen, contains("'Order cancelled successfully.'"));
      expect(screen, contains('failure == null'));
      // …and every failure (including the offline networkError) resolves
      // through the error-message mapper instead.
      expect(screen, contains('_cancellationErrorMessage(failure)'));
      expect(
        screen,
        contains(
          'Unable to cancel the order. Check your connection and try again.',
        ),
      );
    });
  });

  group('FoodOrder — cancellation fields', () {
    test('parses a cancelled order with cancellation metadata', () async {
      final now = DateTime.now();
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('orders').doc('CB-9');
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
        'status': 'cancelled',
        'createdAt': Timestamp.fromDate(now),
        'cancellationDeadline': Timestamp.fromDate(
          now.add(const Duration(minutes: 2)),
        ),
        'cancelledAt': Timestamp.fromDate(now.add(const Duration(minutes: 1))),
        'cancelledBy': 'user_1',
        'cancellationReason': 'Changed my mind',
        'deadlineStatus': 'NOT_READY',
        'pickupWindowMinutes': 20,
      });

      final snapshot = await ref.get();
      final order = FoodOrder.fromFirestore(snapshot);

      expect(order.status, OrderStatus.cancelled);
      expect(order.cancellationDeadline, isNotNull);
      expect(order.cancelledAt, isNotNull);
      expect(order.cancelledBy, 'user_1');
      expect(order.cancellationReason, 'Changed my mind');
    });

    test('restoring an order after an app restart preserves the stored '
        'cancellationDeadline and cancellability', () async {
      // Order placed before the "restart": Firestore holds the
      // server-authoritative deadline (createdAt + 2 min). Here it is still
      // 90 s away when the app is relaunched mid-window.
      final now = DateTime.now();
      final storedDeadline = now.add(const Duration(seconds: 90));
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('orders').doc('CB-restart-1');
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
        'status': 'pending',
        'createdAt': Timestamp.fromDate(now),
        'cancellationDeadline': Timestamp.fromDate(storedDeadline),
        'deadlineStatus': 'NOT_READY',
        'pickupWindowMinutes': 20,
      });

      // Fresh app session: the order is re-read from Firestore exactly as
      // the orders screen does after a restart.
      final snapshot = await ref.get();
      final restored = FoodOrder.fromFirestore(snapshot);

      // The stored server-authoritative deadline survives the round trip —
      // it is not recomputed from the client clock.
      expect(
        restored.cancellationDeadline?.millisecondsSinceEpoch,
        storedDeadline.millisecondsSinceEpoch,
      );
      expect(restored.status, OrderStatus.pending);

      // A fresh ViewModel built for the new session recognises the restored
      // order as cancellable while the deadline is still in the future.
      final vm = OrdersViewModel();
      expect(vm.canCancelOrder(restored), isTrue);

      // Re-serialising the restored order never reintroduces a client-side
      // deadline — the authoritative value is written only by the backend.
      expect(
        restored.toFirestore().containsKey('cancellationDeadline'),
        isFalse,
      );

      // Once the restored deadline has passed, the same restore flow yields
      // an order that is no longer cancellable — the window derives from the
      // stored deadline, not the device clock.
      final expiredRef = firestore.collection('orders').doc('CB-restart-2');
      await expiredRef.set({
        'studentId': 'user_1',
        'userName': 'Test Student',
        'items': const [],
        'price': 0.0,
        'status': 'pending',
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(minutes: 5))),
        'cancellationDeadline': Timestamp.fromDate(
          now.subtract(const Duration(minutes: 1)),
        ),
        'deadlineStatus': 'NOT_READY',
        'pickupWindowMinutes': 20,
      });
      final expiredSnapshot = await expiredRef.get();
      final expired = FoodOrder.fromFirestore(expiredSnapshot);
      expect(vm.canCancelOrder(expired), isFalse);
    });

    test('CANCELLED is the canonical serialized status', () {
      expect(OrderStatus.cancelled.toShortString(), 'cancelled');
      expect(OrderStatus.fromString('cancelled'), OrderStatus.cancelled);
    });

    test('toFirestore never sends a cancellationDeadline on create '
        '(backend-authoritative deadline)', () {
      final order = FoodOrder(
        orderId: 'CB-10',
        userId: 'user_1',
        userName: 'Test',
        items: const [],
        totalAmount: 0,
        orderTime: DateTime.now(),
        status: OrderStatus.pending,
      );
      final data = order.toFirestore();
      // The authoritative deadline is written only by the onNewOrder Cloud
      // Function; the client payload must not carry the key at all.
      expect(data.containsKey('cancellationDeadline'), isFalse);
      expect(data['cancelledAt'], isNull);
      expect(data['cancelledBy'], isNull);
      expect(data['cancellationReason'], isNull);
    });
  });
}
