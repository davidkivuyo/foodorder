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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/models/pickup_reliability.dart';
import 'package:campusbite/widgets/pickup_reliability_card.dart';
import 'package:campusbite/widgets/restriction_notice.dart';

void main() {
  group('Phase F — recovery messaging (§15)', () {
    testWidgets(
      'card shows the recovery message when a restricted student has a '
      'fully collected recent window',
      (tester) async {
        const summary = PickupReliabilitySummary(
          status: PickupReliabilityStatus.poor,
          reliabilityScore: 42.9,
          collectedOrders: 3,
          noShowOrders: 4,
          eligibleOrders: 7,
          recentEligibleOrders: 5,
          recentCollectedOrders: 5,
          recentNoShowOrders: 0,
          recentCollectionRate: 100.0,
          restrictionLevel: PickupRestrictionLevel.limited,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PickupReliabilityCard(summary: summary)),
          ),
        );

        expect(
          find.text(
            'Keep it up — your ordering limits are relaxing as your '
            'pickup reliability improves.',
          ),
          findsOneWidget,
        );
        // The generic praise is replaced, not shown alongside.
        expect(
          find.textContaining("Great job — you've collected"),
          findsNothing,
        );
      },
    );

    testWidgets(
      'card keeps the generic praise when an unrestricted student has a '
      'fully collected recent window',
      (tester) async {
        const summary = PickupReliabilitySummary(
          status: PickupReliabilityStatus.excellent,
          reliabilityScore: 92.0,
          collectedOrders: 18,
          noShowOrders: 2,
          eligibleOrders: 20,
          recentEligibleOrders: 10,
          recentCollectedOrders: 10,
          recentNoShowOrders: 0,
          recentCollectionRate: 100.0,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PickupReliabilityCard(summary: summary)),
          ),
        );

        expect(
          find.text("Great job — you've collected your recent orders on time."),
          findsOneWidget,
        );
        expect(
          find.textContaining('ordering limits are relaxing'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'card shows no recovery message for a restricted student with a '
      'recent no-show',
      (tester) async {
        const summary = PickupReliabilitySummary(
          status: PickupReliabilityStatus.poor,
          reliabilityScore: 42.9,
          collectedOrders: 3,
          noShowOrders: 4,
          eligibleOrders: 7,
          recentEligibleOrders: 5,
          recentCollectedOrders: 4,
          recentNoShowOrders: 1,
          recentCollectionRate: 80.0,
          restrictionLevel: PickupRestrictionLevel.limited,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PickupReliabilityCard(summary: summary)),
          ),
        );

        expect(find.textContaining('ordering limits are relaxing'), findsNothing);
        expect(find.textContaining("Great job"), findsNothing);
      },
    );

    testWidgets(
      'RestrictionNotice shows positive recovery wording for LIMITED',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: RestrictionNotice(
                level: PickupRestrictionLevel.limited,
                activeOrderLimit: 2,
              ),
            ),
          ),
        );

        expect(
          find.textContaining('Your pickup reliability is improving.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('you can now have up to 2 active orders'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'RestrictionNotice shows the automatic relaxation path for '
      'HIGHLY_LIMITED',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: RestrictionNotice(
                level: PickupRestrictionLevel.highlyLimited,
                activeOrderLimit: 1,
              ),
            ),
          ),
        );

        expect(
          find.textContaining('Your pickup reliability is improving.'),
          findsOneWidget,
        );
        // The enforced limit must be stated explicitly, not implied.
        expect(
          find.textContaining('1 active order at a time'),
          findsOneWidget,
        );
        expect(
          find.textContaining('your limit will relax'),
          findsOneWidget,
        );
        // No punitive language anywhere in the recovery messaging.
        expect(find.textContaining('Strike'), findsNothing);
        expect(find.textContaining('Ban'), findsNothing);
        expect(find.textContaining('Suspend'), findsNothing);
        expect(find.textContaining('Penalty'), findsNothing);
      },
    );

    testWidgets(
      'RestrictionNotice renders nothing when the level is NORMAL',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: RestrictionNotice(
                level: PickupRestrictionLevel.normal,
                activeOrderLimit: null,
              ),
            ),
          ),
        );

        expect(find.textContaining('active orders'), findsNothing);
      },
    );
  });

  group('Phase F — Test 12: UI reflects backend recovery automatically', () {
    test('a recovered summary parses and renders the improved state', () {
      // The backend writes the recovered summary to users/{uid}; the app
      // renders whatever the existing user stream delivers. Parsing a
      // recovered summary (HIGHLY_LIMITED → LIMITED → NORMAL) must yield
      // the improved values with no client-side calculation.
      final recovered = PickupReliabilitySummary.fromMap({
        'eligibleOrders': 9,
        'collectedOrders': 5,
        'noShowOrders': 4,
        'collectionRate': 55.6,
        'recentEligibleOrders': 9,
        'recentCollectedOrders': 5,
        'recentNoShowOrders': 4,
        'recentCollectionRate': 55.6,
        'reliabilityScore': 55.6,
        'status': 'NEEDS_IMPROVEMENT',
        'restrictionLevel': 'NORMAL',
        'restrictionReason': null,
      });

      expect(recovered.reliabilityScore, 55.6);
      expect(recovered.restrictionLevel, PickupRestrictionLevel.normal);
      expect(recovered.activeOrderLimit, isNull);
    });

    testWidgets(
      'the card renders a recovered summary without client recalculation',
      (tester) async {
        // The card never recalculates reliability or restriction — it only
        // renders the server-maintained summary, so a backend recovery write
        // is reflected the moment the existing user stream emits it. Pump the
        // recovered summary (HIGHLY_LIMITED → LIMITED → NORMAL) and assert
        // the rendered score/status.
        const recovered = PickupReliabilitySummary(
          status: PickupReliabilityStatus.needsImprovement,
          reliabilityScore: 55.6,
          collectedOrders: 5,
          noShowOrders: 4,
          eligibleOrders: 9,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PickupReliabilityCard(summary: recovered)),
          ),
        );

        expect(find.text('56%'), findsOneWidget); // 55.6 rounds for display
        expect(find.text('Needs Improvement'), findsOneWidget);
        expect(find.text('5 collected · 4 missed'), findsOneWidget);
      },
    );
  });
}
