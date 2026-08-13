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

import 'package:campusbite/models/order.dart';
import 'package:campusbite/widgets/no_show_notice.dart';
import 'package:campusbite/widgets/pickup_countdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase D §24 — Tests 8, 9 & 10: the student-facing no-show / grace-period /
/// hard-cutoff experience is clear and non-punitive.
void main() {
  group('Phase D — no-show & grace period experience', () {
    testWidgets('Test 8 — No-show notice is clear and non-punitive', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NoShowNotice())),
      );

      expect(find.text('No-show recorded'), findsOneWidget);
      expect(
        find.textContaining(
          'The pickup window and grace period ended before the order was '
          'collected.',
        ),
        findsOneWidget,
      );
      // No strike language anywhere.
      expect(find.textContaining('strike'), findsNothing);
      expect(find.textContaining('Strike'), findsNothing);
    });

    testWidgets('Test 9 — Grace period shows active-grace label', (
      tester,
    ) async {
      final now = DateTime.now();
      // 2 minutes past the deadline, within the default 5-minute grace window.
      final inGraceDeadline = now.subtract(const Duration(minutes: 2));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PickupCountdown(
              pickupDeadline: inGraceDeadline,
              deadlineStatus: DeadlineStatus.active,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('Grace period active'),
        findsOneWidget,
      );
    });

    testWidgets('Test 10 — Hard cutoff hides the pickup window label', (
      tester,
    ) async {
      final now = DateTime.now();
      // 20 minutes past the deadline, well beyond the grace window.
      final expiredDeadline = now.subtract(const Duration(minutes: 20));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PickupCountdown(
              pickupDeadline: expiredDeadline,
              deadlineStatus: DeadlineStatus.active,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Pickup window expired'), findsOneWidget);
      // The countdown must not advertise an active pickup period.
      expect(find.textContaining('m '), findsNothing);
    });

    testWidgets('Expired deadline status reads "No-show recorded"', (
      tester,
    ) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PickupCountdown(
              pickupDeadline: now.subtract(const Duration(minutes: 10)),
              deadlineStatus: DeadlineStatus.expired,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No-show recorded'), findsOneWidget);
    });
  });
}
