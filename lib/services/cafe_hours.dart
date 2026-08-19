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

import 'package:cloud_firestore/cloud_firestore.dart';

/// Pure helpers for cafe operating-hours checks.
///
/// Cafe `openAt`/`closingAt` are stored as timezone-free `"HH:mm"` strings in
/// the cafe's local time-of-day. Legacy documents written before the string
/// contract may still carry a `Timestamp`; because a single-campus app assumes
/// the device is in the cafe's timezone, `Timestamp.toDate()` (device-local)
/// yields the intended time-of-day. The comparison "now" is supplied by the
/// caller already in the cafe's timezone (a single-campus app assumes the
/// device is in that zone).
class CafeHours {
  CafeHours._();

  static const int _minutesPerDay = 24 * 60;

  /// Minutes since midnight for [time]. The caller must pass a [DateTime]
  /// whose time-of-day is in the cafe's timezone — never convert server time
  /// with `Timestamp.toDate()` (device-local).
  static int minutesOfDay(DateTime time) => time.hour * 60 + time.minute;

  /// Parses a validated `"HH:mm"` time-of-day (or a legacy `Timestamp`) into
  /// minutes since midnight. Returns `null` when the value is absent or
  /// malformed. The hour must be 00–23 and the minute 00–59 (a 1- or 2-digit
  /// hour is accepted).
  static int? minutesOfDayValue(dynamic value) {
    // Legacy Timestamp hours: toDate() resolves in the device's timezone,
    // which the single-campus assumption equates to the cafe's timezone.
    if (value is Timestamp) return minutesOfDay(value.toDate());
    if (value is! String) return null;
    final parts = value.trim().split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23) return null;
    if (minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  /// Whether [nowMinutes] (minutes since midnight) falls inside the window
  /// `[openMinutes, closeMinutes]`. Handles overnight hours (close < open),
  /// where the window wraps past midnight.
  static bool isOpenAt(
    int nowMinutes,
    int openMinutes,
    int closeMinutes,
  ) {
    if (openMinutes < 0 || closeMinutes < 0) return false;
    if (openMinutes >= _minutesPerDay || closeMinutes >= _minutesPerDay) {
      return false;
    }
    if (closeMinutes >= openMinutes) {
      return nowMinutes >= openMinutes && nowMinutes <= closeMinutes;
    }
    return nowMinutes >= openMinutes || nowMinutes <= closeMinutes;
  }
}