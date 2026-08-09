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
import '../services/pickup_extension_service.dart';

/// ViewModel for [OrdersScreen].
///
/// Owns the order-screen business logic so the widget stays UI-only:
/// - pickup-extension eligibility ([canExtendPickup])
/// - the one-tap pickup extension action ([extendPickup])
/// - the per-order in-progress state ([isExtending])
///
/// The widget only observes this ViewModel and triggers its actions; it never
/// performs eligibility checks or calls services directly.
class OrdersViewModel extends ChangeNotifier {
  OrdersViewModel({PickupExtensionService? pickupExtensionService})
      : _pickupExtensionService =
            pickupExtensionService ?? PickupExtensionService.instance;

  final PickupExtensionService _pickupExtensionService;

  /// Order ID currently being extended, so only that order's card shows the
  /// in-progress state while other ready orders stay interactive.
  String? _extendingOrderId;

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
