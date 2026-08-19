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

import 'package:flutter/foundation.dart';
import '../models/order.dart';
import '../services/order_cancellation_service.dart';
import '../services/pickup_extension_service.dart';

/// ViewModel for [OrdersScreen].
///
/// Owns the order-screen business logic so the widget stays UI-only:
/// - pickup-extension eligibility ([canExtendPickup])
/// - the one-tap pickup extension action ([extendPickup])
/// - order cancellation eligibility ([canCancelOrder]) and the cancel action
///   ([cancelOrder])
/// - the per-order in-progress states ([isExtending], [isCancelling])
///
/// The widget only observes this ViewModel and triggers its actions; it never
/// performs eligibility checks or calls services directly.
class OrdersViewModel extends ChangeNotifier {
  OrdersViewModel({
    PickupExtensionService? pickupExtensionService,
    OrderCancellationService? cancellationService,
  })  : _pickupExtensionService =
            pickupExtensionService ?? PickupExtensionService.instance,
        _cancellationService =
            cancellationService ?? OrderCancellationService.instance;

  final PickupExtensionService _pickupExtensionService;
  final OrderCancellationService _cancellationService;

  /// Order ID currently being extended, so only that order's card shows the
  /// in-progress state while other ready orders stay interactive.
  String? _extendingOrderId;

  /// Order IDs currently being cancelled, so each order's card shows its own
  /// in-progress state. A Set (not a single slot) keeps concurrent requests
  /// independent: completing one order's cancellation must never clear
  /// another order's loading state.
  final Set<String> _cancellingOrderIds = {};

  bool _disposed = false;

  /// Whether [orderId] is the order currently being extended.
  bool isExtending(String orderId) => _extendingOrderId == orderId;

  /// Whether the student may still extend this order's pickup deadline.
  ///
  /// Available exactly once, only while the order is ready and its pickup
  /// deadline has not yet passed.
  bool canExtendPickup(FoodOrder order) {
    if (order.status != OrderStatus.ready) return false;
    if (order.deadlineStatus != DeadlineStatus.active) return false;
    if (order.deadlineExtended) return false;
    final deadline = order.pickupDeadline;
    if (deadline == null) return false;
    return deadline.isAfter(DateTime.now());
  }

  /// Extends the order's pickup deadline by
  /// [PickupExtensionService.extensionMinutes] (once per order).
  ///
  /// Returns a [PickupExtensionResult]: `failure` is null on success and
  /// [PickupExtensionResult.newDeadline] carries the server-returned deadline;
  /// on failure, `failure` is a stable [PickupExtensionFailure] value that the
  /// view resolves to a user-facing message.
  Future<PickupExtensionResult> extendPickup(String orderId) async {
    _extendingOrderId = orderId;
    _safeNotify();
    try {
      return await _pickupExtensionService.extendPickupDeadline(orderId);
    } finally {
      _extendingOrderId = null;
      _safeNotify();
    }
  }

  /// Whether [orderId] is currently being cancelled.
  bool isCancelling(String orderId) => _cancellingOrderIds.contains(orderId);

  /// Whether the student may still cancel this order.
  ///
  /// True only while the order is still pending and the server-authoritative
  /// cancellation deadline has not passed. The countdown is derived from the
  /// same [FoodOrder.cancellationDeadline] in the UI.
  bool canCancelOrder(FoodOrder order) {
    if (order.status != OrderStatus.pending) return false;
    final deadline = order.cancellationDeadline;
    if (deadline == null) return false;
    return deadline.isAfter(DateTime.now());
  }

  /// Cancels [orderId] through the backend `cancelOrder` callable.
  ///
  /// Returns an [OrderCancellationResult]: `failure` is null on success and a
  /// stable [OrderCancellationFailure] value on failure that the view resolves
  /// to a user-facing message.
  Future<OrderCancellationResult> cancelOrder(
    String orderId, {
    String? reason,
  }) async {
    _cancellingOrderIds.add(orderId);
    _safeNotify();
    try {
      return await _cancellationService.cancelOrder(
        orderId,
        reason: reason,
      );
    } finally {
      _cancellingOrderIds.remove(orderId);
      _safeNotify();
    }
  }

  /// Stops notifying listeners once this ViewModel has been disposed so that
  /// pending async operations can settle without touching a dead notifier.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
