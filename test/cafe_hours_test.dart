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
import 'package:campusbite/services/cafe_hours.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CafeHours.minutesOfDay', () {
    test('converts time to minutes since midnight', () {
      final t = DateTime(2026, 1, 1, 8, 30);
      expect(CafeHours.minutesOfDay(t), 8 * 60 + 30);
      expect(CafeHours.minutesOfDay(DateTime(2026, 1, 1, 0, 0)), 0);
      expect(CafeHours.minutesOfDay(DateTime(2026, 1, 1, 23, 59)), 1439);
    });
  });

  group('CafeHours.minutesOfDayValue', () {
    test('parses "HH:mm" strings', () {
      expect(CafeHours.minutesOfDayValue('08:00'), 480);
      expect(CafeHours.minutesOfDayValue('21:30'), 1290);
    });

    test('accepts a single-digit hour', () {
      expect(CafeHours.minutesOfDayValue('8:00'), 480);
      expect(CafeHours.minutesOfDayValue('09:05'), 545);
    });

    test('rejects out-of-range hours and minutes', () {
      expect(CafeHours.minutesOfDayValue('24:00'), isNull);
      expect(CafeHours.minutesOfDayValue('08:60'), isNull);
      expect(CafeHours.minutesOfDayValue('-1:00'), isNull);
      expect(CafeHours.minutesOfDayValue('8:99'), isNull);
    });

    test('parses a legacy Timestamp as its local time-of-day', () {
      // Timestamp.fromDate preserves the wall-clock time through toDate() in
      // the device's zone, which the single-campus assumption equates to the
      // cafe's zone.
      expect(
        CafeHours.minutesOfDayValue(
          Timestamp.fromDate(DateTime(2026, 8, 18, 8, 30)),
        ),
        8 * 60 + 30,
      );
      expect(
        CafeHours.minutesOfDayValue(
          Timestamp.fromDate(DateTime(2026, 8, 18, 22, 0)),
        ),
        22 * 60,
      );
      expect(
        CafeHours.minutesOfDayValue(
          Timestamp.fromDate(DateTime(2026, 8, 18, 23, 59)),
        ),
        1439,
      );
    });

    test('returns null for absent, non-string, or malformed values', () {
      expect(CafeHours.minutesOfDayValue(null), isNull);
      expect(CafeHours.minutesOfDayValue(''), isNull);
      expect(CafeHours.minutesOfDayValue('abc'), isNull);
      expect(CafeHours.minutesOfDayValue('8:00:00'), isNull);
      expect(CafeHours.minutesOfDayValue(480), isNull);
      expect(CafeHours.minutesOfDayValue(true), isNull);
    });
  });

  group('CafeHours.isOpenAt', () {
    test('regular window during the day', () {
      // 08:00 - 21:00
      expect(CafeHours.isOpenAt(8 * 60, 480, 1260), isTrue);
      expect(CafeHours.isOpenAt(12 * 60, 480, 1260), isTrue);
      expect(CafeHours.isOpenAt(21 * 60, 480, 1260), isTrue);
      expect(CafeHours.isOpenAt(7 * 60 + 59, 480, 1260), isFalse);
      expect(CafeHours.isOpenAt(21 * 60 + 1, 480, 1260), isFalse);
    });

    test('overnight window wraps past midnight', () {
      // 22:00 - 06:00
      expect(CafeHours.isOpenAt(23 * 60, 1320, 360), isTrue);
      expect(CafeHours.isOpenAt(5 * 60, 1320, 360), isTrue);
      expect(CafeHours.isOpenAt(6 * 60, 1320, 360), isTrue);
      expect(CafeHours.isOpenAt(12 * 60, 1320, 360), isFalse);
      expect(CafeHours.isOpenAt(7 * 60, 1320, 360), isFalse);
    });

    test('rejects out-of-range minutes', () {
      expect(CafeHours.isOpenAt(0, -1, 360), isFalse);
      expect(CafeHours.isOpenAt(0, 480, 1500), isFalse);
    });
  });
}