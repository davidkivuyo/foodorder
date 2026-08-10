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
/// [OrderCancellationService.cancelOrder].
///
/// The consuming UI resolves each value to a user-facing message (English is
/// the default locale); the service never produces display strings itself.
enum OrderCancellationFailure {
  /// The order no longer exists.
  notFound,

  /// The caller is not allowed to cancel this order (ownership mismatch).
  permissionDenied,

  /// The order can no longer be cancelled (not pending, or the 2-minute
  /// cancellation window has expired).
  failedPrecondition,

  /// The caller is not authenticated.
  unauthenticated,

  /// The Cloud Function could not be reached.
  unavailable,

  /// The callable was reached but rejected with an unexpected code.
  failed,

  /// An unexpected client-side exception (e.g. transport/connectivity error).
  networkError,
}

/// Result of a cancellation attempt. `failure` is null exactly when the
/// cancellation succeeded.
typedef OrderCancellationResult = ({OrderCancellationFailure? failure});

/// Cancels an order within the 2-minute cancellation window.
///
/// The actual state transition is performed by the `cancelOrder` callable
/// Cloud Function because students cannot update order documents directly
/// (Firestore rules only allow admin order updates). The callable verifies
/// ownership, pending status and the authoritative server-side deadline.
class OrderCancellationService {
  final FirebaseFunctions? _functions;

  /// [functions] is injectable for tests and defaults to the shared
  /// [FirebaseFunctions.instance] at call time (mirrors the repo's
  /// optional-injection pattern, e.g. CartService). Resolved lazily so the
  /// [instance] singleton never touches Firebase during construction — tests
  /// that construct [OrdersViewModel] without initializing Firebase stay
  /// green. Public so ViewModels can inject fakes in tests (subclassable
  /// service pattern, e.g. AuthService).
  OrderCancellationService({FirebaseFunctions? functions})
      : _functions = functions; // ignore: prefer_initializing_formals

  static final OrderCancellationService instance =
      OrderCancellationService();

  /// Length of the cancellation window in minutes.
  /// Matches the backend CANCELLATION_WINDOW_MINUTES constant.
  static const int windowMinutes = 2;

  /// The preset cancellation reasons accepted by the backend callable.
  static const List<String> cancellationReasons = [
    'Changed my mind',
    'Ordered by mistake',
    'Need to change my order',
    'Ordered the wrong item',
    'Other',
  ];

  /// Cancels [orderId] with an optional preset [reason].
  ///
  /// Returns an [OrderCancellationResult]: `failure` is null on success and
  /// a stable [OrderCancellationFailure] value on failure that the caller
  /// resolves to a localized user message.
  Future<OrderCancellationResult> cancelOrder(
    String orderId, {
    String? reason,
  }) async {
    try {
      final callable =
          (_functions ?? FirebaseFunctions.instance).httpsCallable('cancelOrder');
      await callable.call({
        'orderId': orderId,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });
      return (failure: null);
    } on FirebaseFunctionsException catch (e) {
      AppLog.w('[OrderCancellationService] cancelOrder rejected: ${e.code}');
      final failure = switch (e.code) {
        'not-found' => OrderCancellationFailure.notFound,
        'permission-denied' => OrderCancellationFailure.permissionDenied,
        'failed-precondition' => OrderCancellationFailure.failedPrecondition,
        'unauthenticated' => OrderCancellationFailure.unauthenticated,
        'unavailable' => OrderCancellationFailure.unavailable,
        _ => OrderCancellationFailure.failed,
      };
      return (failure: failure);
    } on Exception catch (e, stack) {
      AppLog.e('[OrderCancellationService] cancelOrder error', e, stack);
      return (failure: OrderCancellationFailure.networkError);
    }
  }
}
