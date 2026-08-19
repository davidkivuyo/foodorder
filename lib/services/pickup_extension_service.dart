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
/// [PickupExtensionService.extendPickupDeadline].
///
/// The consuming UI resolves each value to a user-facing message (English is
/// the default locale); the service never produces display strings itself, so
/// it stays free of presentation concerns and server-provided message text.
enum PickupExtensionFailure {
  /// The order no longer exists.
  notFound,

  /// The caller is not allowed to extend this order.
  permissionDenied,

  /// The order can no longer be extended (not ready, deadline passed, or the
  /// one-time extension was already used).
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

/// Result of a pickup-extension attempt.
///
/// `failure` is null exactly when the extension succeeded; on success
/// [newDeadline] carries the server-returned deadline (null only if the
/// response was malformed, in which case the caller falls back to its
/// existing value).
typedef PickupExtensionResult = ({PickupExtensionFailure? failure, DateTime? newDeadline});

/// Extends an order's pickup deadline by a fixed amount (once per order).
///
/// The actual write is performed by the `extendPickupDeadline` callable
/// Cloud Function because students cannot update order documents directly
/// (Firestore rules only allow admin order updates).
class PickupExtensionService {
  /// Public so ViewModels can inject fakes in tests (mirrors the repo's
  /// subclassable service pattern, e.g. AuthService).
  PickupExtensionService();

  static final PickupExtensionService instance = PickupExtensionService();

  /// Number of minutes a single extension adds to the pickup deadline.
  static const int extensionMinutes = 10;

  /// Extends the pickup deadline of [orderId] by [extensionMinutes].
  ///
  /// Returns a [PickupExtensionResult]: `failure` is null on success and
  /// [PickupExtensionResult.newDeadline] carries the deadline returned by the
  /// callable (the UI can update an open countdown immediately instead of
  /// waiting for the orders stream to rebuild). On failure, `failure` is a
  /// stable [PickupExtensionFailure] value that the caller resolves to a
  /// localized user message.
  Future<PickupExtensionResult> extendPickupDeadline(String orderId) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'extendPickupDeadline',
      );
      final response = await callable.call({'orderId': orderId});
      final data = response.data;
      DateTime? newDeadline;
      if (data is Map) {
        final raw = data['pickupDeadline'];
        if (raw is String) {
          newDeadline = DateTime.tryParse(raw);
        }
      }
      return (failure: null, newDeadline: newDeadline);
    } on FirebaseFunctionsException catch (e) {
      AppLog.w('[PickupExtensionService] extendPickupDeadline rejected: ${e.code}');
      final failure = switch (e.code) {
        'not-found' => PickupExtensionFailure.notFound,
        'permission-denied' => PickupExtensionFailure.permissionDenied,
        'failed-precondition' => PickupExtensionFailure.failedPrecondition,
        'unauthenticated' => PickupExtensionFailure.unauthenticated,
        'unavailable' => PickupExtensionFailure.unavailable,
        _ => PickupExtensionFailure.failed,
      };
      return (failure: failure, newDeadline: null);
    } on Exception catch (e, stack) {
      AppLog.e('[PickupExtensionService] extendPickupDeadline error', e, stack);
      return (failure: PickupExtensionFailure.networkError, newDeadline: null);
    }
  }
}
