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
import 'package:cloud_functions/cloud_functions.dart';
import 'app_log.dart';

/// Fetches the authoritative Cloud Functions clock so the client can evaluate
/// time-of-day rules (e.g. cafe open/closed) without trusting the device clock.
///
/// The callable is deliberately cheap and has no Firestore access. Callers
/// MUST treat a `null` result (offline, timeout, disabled function) as
/// "status unknown" and fail closed — they must never fall back to the device
/// clock for a time-restricted decision.
class ServerClockService {
  final FirebaseFunctions? _functions;

  // Expected failures (offline/timeout/unavailable) are logged at warning
  // level and rate-limited, so a long outage or the periodic screen refresh
  // does not flood the error log. Unexpected failures and malformed responses
  // still log at error level.
  static const Duration _expectedFailureLogCooldown = Duration(minutes: 5);
  DateTime? _lastExpectedFailureLoggedAt;

  ServerClockService({FirebaseFunctions? functions})
      : _functions = functions; // ignore: prefer_initializing_formals

  /// Returns the server's current UTC time, or `null` if unavailable.
  Future<DateTime?> getServerTime() async {
    try {
      final callable = (_functions ?? FirebaseFunctions.instance)
          .httpsCallable('getServerTime');
      final result = await callable
          .call<Map<String, dynamic>>()
          .timeout(const Duration(seconds: 5));
      final nowMillis = result.data['nowMillis'];
      if (nowMillis is! num) {
        AppLog.e('[ServerClockService] getServerTime malformed response');
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(nowMillis.toInt(), isUtc: true);
    } on TimeoutException {
      _logExpectedFailure('timeout');
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (_isExpectedFailureCode(e.code)) {
        _logExpectedFailure('code=${e.code}');
      } else {
        AppLog.e('[ServerClockService] getServerTime error: code=${e.code}', e);
      }
      return null;
    } catch (e) {
      AppLog.e('[ServerClockService] getServerTime error: type=${e.runtimeType}');
      return null;
    }
  }

  /// Transient/expected callable codes that merely mean "server clock
  /// unavailable right now" — the caller already fails closed on `null`.
  static bool _isExpectedFailureCode(String code) {
    return switch (code) {
      'unavailable' ||
      'deadline-exceeded' ||
      'cancelled' ||
      'aborted' ||
      'unauthenticated' =>
        true,
      _ => false,
    };
  }

  void _logExpectedFailure(String detail) {
    final now = DateTime.now();
    final last = _lastExpectedFailureLoggedAt;
    if (last != null &&
        now.difference(last) < _expectedFailureLogCooldown) {
      return;
    }
    _lastExpectedFailureLoggedAt = now;
    AppLog.w('[ServerClockService] getServerTime unavailable: $detail');
  }
}