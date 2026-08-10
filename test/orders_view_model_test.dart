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

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:campusbite/models/order.dart';
import 'package:campusbite/services/order_cancellation_service.dart';
import 'package:campusbite/services/pickup_extension_service.dart';
import 'package:campusbite/viewmodels/orders_view_model.dart';

/// [PickupExtensionService] whose extension call can be held open by the test
/// until resolved, so the ViewModel's in-flight state and dispose safety can
/// be verified deterministically.
class _HeldPickupExtensionService extends PickupExtensionService {
  final Completer<PickupExtensionResult> completer =
      Completer<PickupExtensionResult>();

  bool extendCalled = false;

  @override
  Future<PickupExtensionResult> extendPickupDeadline(String orderId) {
    extendCalled = true;
    return completer.future;
  }
}

/// [OrderCancellationService] whose cancellation calls can be held open per
/// order and resolved by the test, so the ViewModel's per-order in-flight
/// state can be verified deterministically under concurrency.
class _HeldOrderCancellationService extends OrderCancellationService {
  final Map<String, Completer<OrderCancellationResult>> completers = {};

  @override
  Future<OrderCancellationResult> cancelOrder(
    String orderId, {
    String? reason,
  }) {
    final completer = Completer<OrderCancellationResult>();
    completers[orderId] = completer;
    return completer.future;
  }

  void complete(String orderId, OrderCancellationResult result) {
    completers.remove(orderId)?.complete(result);
  }
}

FoodOrder _order({
  String id = 'o1',
  OrderStatus status = OrderStatus.ready,
  DeadlineStatus deadlineStatus = DeadlineStatus.active,
  DateTime? deadline,
  bool extended = false,
}) {
  return FoodOrder(
    orderId: id,
    userId: 'u1',
    userName: 'Tester',
    items: const [],
    totalAmount: 0,
    orderTime: DateTime.now(),
    status: status,
    deadlineStatus: deadlineStatus,
    pickupDeadline: deadline ?? DateTime.now().add(const Duration(minutes: 30)),
    deadlineExtended: extended,
  );
}

void main() {
  group('OrdersViewModel.canExtendPickup', () {
    test('true for a ready, active, unused order with a future deadline', () {
      final vm = OrdersViewModel();
      expect(vm.canExtendPickup(_order()), isTrue);
    });

    test('false when the order is not ready', () {
      final vm = OrdersViewModel();
      expect(vm.canExtendPickup(_order(status: OrderStatus.preparing)), isFalse);
    });

    test('false when the deadline status is not active', () {
      final vm = OrdersViewModel();
      expect(
        vm.canExtendPickup(_order(deadlineStatus: DeadlineStatus.notReady)),
        isFalse,
      );
    });

    test('false when the extension was already used', () {
      final vm = OrdersViewModel();
      expect(vm.canExtendPickup(_order(extended: true)), isFalse);
    });

    test('false when the pickup deadline is missing', () {
      final vm = OrdersViewModel();
      expect(
        vm.canExtendPickup(
          FoodOrder(
            orderId: 'o1',
            userId: 'u1',
            userName: 'Tester',
            items: const [],
            totalAmount: 0,
            orderTime: DateTime.now(),
            status: OrderStatus.ready,
            deadlineStatus: DeadlineStatus.active,
          ),
        ),
        isFalse,
      );
    });

    test('false when the pickup deadline has already passed', () {
      final vm = OrdersViewModel();
      expect(
        vm.canExtendPickup(
          _order(deadline: DateTime.now().subtract(const Duration(minutes: 1))),
        ),
        isFalse,
      );
    });
  });

  group('OrdersViewModel.extendPickup', () {
    test('marks only the in-flight order as extending, then clears it', () async {
      final service = _HeldPickupExtensionService();
      final vm = OrdersViewModel(pickupExtensionService: service);

      final future = vm.extendPickup('o1');
      // The call must actually be in flight before we assert state.
      expect(service.extendCalled, isTrue);
      expect(vm.isExtending('o1'), isTrue);
      expect(vm.isExtending('o2'), isFalse);

      final newDeadline = DateTime.now().add(const Duration(minutes: 40));
      service.completer.complete((failure: null, newDeadline: newDeadline));
      final result = await future;
      expect(result.failure, isNull);
      expect(result.newDeadline, newDeadline);
      expect(vm.isExtending('o1'), isFalse);
    });

    test('returns the failure value and still clears the in-flight state', () async {
      final service = _HeldPickupExtensionService();
      final vm = OrdersViewModel(pickupExtensionService: service);

      final future = vm.extendPickup('o1');
      expect(vm.isExtending('o1'), isTrue);

      service.completer.complete((
        failure: PickupExtensionFailure.failedPrecondition,
        newDeadline: null,
      ));
      final result = await future;
      expect(result.failure, PickupExtensionFailure.failedPrecondition);
      expect(result.newDeadline, isNull);
      expect(vm.isExtending('o1'), isFalse);
    });

    test('settling after dispose does not throw', () async {
      final service = _HeldPickupExtensionService();
      final vm = OrdersViewModel(pickupExtensionService: service);

      final future = vm.extendPickup('o1');
      expect(service.extendCalled, isTrue);
      vm.dispose();
      service.completer.complete((failure: null, newDeadline: null));

      await expectLater(future, completes);
    });
  });

  group('OrdersViewModel.cancelOrder — concurrent in-flight state', () {
    test('tracks each order independently so one completion never clears '
        'another order\'s loading state', () async {
      final service = _HeldOrderCancellationService();
      final vm = OrdersViewModel(cancellationService: service);

      final cancelA = vm.cancelOrder('oA');
      final cancelB = vm.cancelOrder('oB');

      // Both requests are in flight at once — each order is marked
      // independently, and neither is conflated with the other.
      expect(vm.isCancelling('oA'), isTrue);
      expect(vm.isCancelling('oB'), isTrue);

      // Completing order A must NOT clear order B's in-flight state.
      service.complete('oA', (failure: null));
      final resultA = await cancelA;
      expect(resultA.failure, isNull);
      expect(vm.isCancelling('oA'), isFalse);
      expect(vm.isCancelling('oB'), isTrue);

      // Completing order B clears only B's state.
      service.complete('oB', (failure: OrderCancellationFailure.networkError));
      final resultB = await cancelB;
      expect(resultB.failure, OrderCancellationFailure.networkError);
      expect(vm.isCancelling('oB'), isFalse);
      expect(vm.isCancelling('oA'), isFalse);
    });

    test('marks only the cancelled order while others stay interactive', () async {
      final service = _HeldOrderCancellationService();
      final vm = OrdersViewModel(cancellationService: service);

      final future = vm.cancelOrder('oA');
      expect(vm.isCancelling('oA'), isTrue);
      expect(vm.isCancelling('oB'), isFalse);

      service.complete('oA', (failure: null));
      await future;
      expect(vm.isCancelling('oA'), isFalse);
    });
  });
}
