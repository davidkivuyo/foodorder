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

import 'package:cloud_functions/cloud_functions.dart';
import 'app_log.dart';

/// Stable, non-user-facing failure values returned by
/// [OrderPlacementService.placeOrder].
///
/// The consuming UI resolves each value to a user-facing message (English is
/// the default locale); the service never produces display strings itself.
enum OrderPlacementFailure {
  /// The student is at the active-order limit for their restriction level
  /// (Phase E). The authoritative decision comes from the backend callable.
  activeOrderLimit,

  /// The backend could not verify the active-order count — the order was
  /// deliberately NOT created (fail-safe; no client fallback is allowed).
  unableToVerify,

  /// The caller is not authenticated.
  unauthenticated,

  /// The caller is not allowed to place this order (ownership mismatch or a
  /// suspended account).
  permissionDenied,

  /// Some items are no longer available.
  unavailableFood,

  /// The request payload was rejected as invalid.
  invalidPayload,

  /// The callable was reached but rejected with an unexpected code.
  failed,

  /// An unexpected client-side exception (e.g. transport/connectivity error).
  networkError,
}

/// Result of an order-placement attempt. `failure` is null exactly when the
/// order was created; [orderId] then carries the created order's ID and
/// [activeOrderLimit] the limit that was in force (null when unrestricted).
typedef OrderPlacementResult = ({
  String? orderId,
  OrderPlacementFailure? failure,
  int? activeOrderLimit,
});

/// Places orders through the backend `placeOrder` callable.
///
/// Phase E moved authoritative order creation from a direct client Firestore
/// write to this callable so the backend can enforce the graduated
/// active-order limit (Firestore Rules cannot count documents across a
/// collection). The callable also re-checks food availability and verifies
/// the student's restriction state before creating the order.
class OrderPlacementService {
  final FirebaseFunctions? _functions;

  /// [functions] is injectable for tests and defaults to the shared
  /// [FirebaseFunctions.instance] at call time (mirrors the repo's
  /// optional-injection pattern, e.g. OrderCancellationService). Resolved
  /// lazily so the [instance] singleton never touches Firebase during
  /// construction. Public so ViewModels/services can inject fakes in tests.
  OrderPlacementService({FirebaseFunctions? functions})
      : _functions = functions; // ignore: prefer_initializing_formals

  static final OrderPlacementService instance = OrderPlacementService();

  /// Places [orderData] (the serialized order payload) through the
  /// `placeOrder` callable.
  ///
  /// Returns an [OrderPlacementResult]: `failure` is null and [orderId] is
  /// set on success; otherwise [failure] is a stable [OrderPlacementFailure]
  /// value the view resolves to a user-facing message.
  Future<OrderPlacementResult> placeOrder(Map<String, dynamic> orderData) async {
    try {
      final callable =
          (_functions ?? FirebaseFunctions.instance).httpsCallable('placeOrder');
      final response = await callable.call(orderData);
      final data = response.data;
      final orderId = data is Map && data['orderId'] is String
          ? data['orderId'] as String
          : null;
      if (orderId == null) {
        return (
          orderId: null,
          failure: OrderPlacementFailure.failed,
          activeOrderLimit: null,
        );
      }
      return (orderId: orderId, failure: null, activeOrderLimit: null);
    } on FirebaseFunctionsException catch (e) {
      AppLog.w('[OrderPlacementService] placeOrder rejected: ${e.code}');
      final details = e.details;
      final subCode = details is Map ? details['code'] : null;
      if (e.code == 'failed-precondition' && subCode == 'ACTIVE_ORDER_LIMIT') {
        final limit = details is Map ? details['activeOrderLimit'] : null;
        return (
          orderId: null,
          failure: OrderPlacementFailure.activeOrderLimit,
          activeOrderLimit: limit is num ? limit.toInt() : null,
        );
      }
      final failure = switch (e.code) {
        'failed-precondition' when subCode == 'ITEMS_UNAVAILABLE' =>
          OrderPlacementFailure.unavailableFood,
        'unavailable' => OrderPlacementFailure.unableToVerify,
        'unauthenticated' => OrderPlacementFailure.unauthenticated,
        'permission-denied' => OrderPlacementFailure.permissionDenied,
        'invalid-argument' => OrderPlacementFailure.invalidPayload,
        _ => OrderPlacementFailure.failed,
      };
      return (
        orderId: null,
        failure: failure,
        activeOrderLimit: null,
      );
    } on Exception catch (e) {
      AppLog.e('[OrderPlacementService] Error placing order', e);
      return (
        orderId: null,
        failure: OrderPlacementFailure.networkError,
        activeOrderLimit: null,
      );
    }
  }
}
