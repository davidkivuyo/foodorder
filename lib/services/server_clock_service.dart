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

/// Fetches the authoritative Cloud Functions clock so the client can evaluate
/// time-of-day rules (e.g. cafe open/closed) without trusting the device clock.
///
/// The callable is deliberately cheap and has no Firestore access. Callers
/// MUST treat a `null` result (offline, timeout, disabled function) as
/// "status unknown" and fail closed — they must never fall back to the device
/// clock for a time-restricted decision.
class ServerClockService {
  final FirebaseFunctions? _functions;

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
      if (nowMillis is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(nowMillis.toInt(), isUtc: true);
    } catch (e) {
      AppLog.e('[ServerClockService] getServerTime error: type=${e.runtimeType}');
      return null;
    }
  }
}