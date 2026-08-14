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
import 'package:campusbite/widgets/extend_pickup_action.dart';
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

  group('ExtendPickupAction — self-expiring at the deadline', () {
    Widget wrap(ExtendPickupAction action) {
      return MaterialApp(home: Scaffold(body: Center(child: action)));
    }

    testWidgets('shows the extend button while the deadline is in the future', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ExtendPickupAction(
            canExtend: true,
            extended: false,
            isExtending: false,
            pickupDeadline: DateTime.now().add(const Duration(minutes: 5)),
            onExtend: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Extend pickup by 10 min'),
        findsOneWidget,
      );
    });

    testWidgets('hides the extend button once the deadline passes (grace period)', (
      tester,
    ) async {
      // 2 minutes past the deadline — inside the default 5-minute grace window.
      final inGraceDeadline = DateTime.now().subtract(const Duration(minutes: 2));

      await tester.pumpWidget(
        wrap(
          ExtendPickupAction(
            canExtend: true,
            extended: false,
            isExtending: false,
            pickupDeadline: inGraceDeadline,
            onExtend: () {},
          ),
        ),
      );
      await tester.pump();

      // The action must not be offered during the grace period — tapping it
      // would only produce a confusing rejection from the callable.
      expect(find.text('Extend pickup by 10 min'), findsNothing);
    });

    testWidgets('hides the button when the deadline elapses while mounted', (
      tester,
    ) async {
      // Injectable clock so the timer test is deterministic: the widget starts
      // visible, then the clock advances past the deadline and the internal
      // 1-second timer must hide the action without any parent rebuild.
      var now = DateTime(2026, 8, 1, 12, 0, 0);
      final deadline = now.add(const Duration(minutes: 5));

      await tester.pumpWidget(
        wrap(
          ExtendPickupAction(
            canExtend: true,
            extended: false,
            isExtending: false,
            pickupDeadline: deadline,
            onExtend: () {},
            clock: () => now,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Extend pickup by 10 min'), findsOneWidget);

      // Advance the clock past the deadline, then let the timer tick.
      now = deadline.add(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text('Extend pickup by 10 min'), findsNothing);
    });

    testWidgets('shows the extended chip once the extension is used', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ExtendPickupAction(
            canExtend: false,
            extended: true,
            isExtending: false,
            pickupDeadline: DateTime.now().add(const Duration(minutes: 5)),
            onExtend: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Pickup extended by 10 min'),
        findsOneWidget,
      );
    });

    testWidgets('renders nothing when neither extendable nor extended', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ExtendPickupAction(
            canExtend: false,
            extended: false,
            isExtending: false,
            pickupDeadline: null,
            onExtend: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('Extend pickup by 10 min'), findsNothing);
      expect(find.text('Pickup extended by 10 min'), findsNothing);
    });

    testWidgets('runs no timer when there is no pickupDeadline to watch', (
      tester,
    ) async {
      // No deadline means nothing can expire, so the widget must not start a
      // 1-second periodic timer that could never self-cancel.
      await tester.pumpWidget(
        wrap(
          ExtendPickupAction(
            canExtend: true,
            extended: false,
            isExtending: false,
            pickupDeadline: null,
            onExtend: () {},
          ),
        ),
      );
      await tester.pump();

      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
