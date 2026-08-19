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

import 'package:campusbite/models/pickup_reliability.dart';
// ignore: unused_import
import 'package:campusbite/models/user_profile.dart';
import 'package:campusbite/widgets/pickup_reliability_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PickupReliabilityCard Widget Tests (Phase D)', () {
    testWidgets('Test 1 — New user shows "New record" and constructive message', (
      tester,
    ) async {
      const summary = PickupReliabilitySummary(
        status: PickupReliabilityStatus.newUser,
        eligibleOrders: 0,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PickupReliabilityCard(summary: summary)),
        ),
      );

      expect(find.text('New record'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(
        find.text(
          'Your pickup record will appear after you complete your first order.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'Test 2 — Insufficient history shows "Building record" without punishment',
      (tester) async {
        const summary = PickupReliabilitySummary(
          status: PickupReliabilityStatus.insufficientHistory,
          eligibleOrders: 2,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PickupReliabilityCard(summary: summary)),
          ),
        );

        expect(find.text('Building record'), findsOneWidget);
        expect(find.text('—'), findsOneWidget);
        expect(
          find.text(
            'Building your pickup record. Keep collecting your orders on time.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Test 3 — Excellent status renders score, stats, and green badge',
      (tester) async {
        const summary = PickupReliabilitySummary(
          status: PickupReliabilityStatus.excellent,
          reliabilityScore: 95.0,
          collectedOrders: 19,
          noShowOrders: 1,
          eligibleOrders: 20,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PickupReliabilityCard(summary: summary)),
          ),
        );

        expect(find.text('Excellent'), findsOneWidget);
        expect(find.text('95%'), findsOneWidget);
        expect(find.text('19 collected · 1 missed'), findsOneWidget);
        expect(
          find.text(
            'Excellent pickup record. Thank you for collecting your orders on time.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Test 4 — Good status renders score and constructive message',
      (tester) async {
        const summary = PickupReliabilitySummary(
          status: PickupReliabilityStatus.good,
          reliabilityScore: 82.0,
          collectedOrders: 16,
          noShowOrders: 4,
          eligibleOrders: 20,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PickupReliabilityCard(summary: summary)),
          ),
        );

        expect(find.text('Good'), findsOneWidget);
        expect(find.text('82%'), findsOneWidget);
        expect(
          find.text('Good pickup record. Keep collecting your orders on time.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Test 5 — Needs Improvement status shows constructive message',
      (tester) async {
        const summary = PickupReliabilitySummary(
          status: PickupReliabilityStatus.needsImprovement,
          reliabilityScore: 65.0,
          collectedOrders: 13,
          noShowOrders: 7,
          eligibleOrders: 20,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PickupReliabilityCard(summary: summary)),
          ),
        );

        expect(find.text('Needs Improvement'), findsOneWidget);
        expect(find.text('65%'), findsOneWidget);
        expect(
          find.text(
            'Your pickup record needs improvement. Please try to collect your orders within the pickup period.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Test 6 — Poor status renders non-punitive constructive reminder',
      (tester) async {
        const summary = PickupReliabilitySummary(
          status: PickupReliabilityStatus.poor,
          reliabilityScore: 45.0,
          collectedOrders: 9,
          noShowOrders: 11,
          eligibleOrders: 20,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PickupReliabilityCard(summary: summary)),
          ),
        );

        expect(find.text('Poor'), findsOneWidget);
        expect(find.text('45%'), findsOneWidget);
        expect(
          find.text(
            'Please remember to collect your orders during the pickup window to help reduce food waste.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Test 7 — Critical status shows constructive reminder without restriction',
      (tester) async {
        const summary = PickupReliabilitySummary(
          status: PickupReliabilityStatus.critical,
          reliabilityScore: 20.0,
          collectedOrders: 4,
          noShowOrders: 16,
          eligibleOrders: 20,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PickupReliabilityCard(summary: summary)),
          ),
        );

        expect(find.text('Critical'), findsOneWidget);
        expect(find.text('20%'), findsOneWidget);
        expect(
          find.text(
            'Please make every effort to collect future orders within the pickup period.',
          ),
          findsOneWidget,
        );
        // No restrictions or punishment language.
        expect(find.textContaining('restricted'), findsNothing);
        expect(find.textContaining('banned'), findsNothing);
      },
    );

    testWidgets(
      'Test 8 — Recent success shows positive reinforcement (Phase D §11)',
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
          find.text('Last 10 pickups: 10 collected · 0 missed'),
          findsOneWidget,
        );
        expect(
          find.text("Great job — you've collected your recent orders on time."),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Test 9 — No recent success means no encouragement shown',
      (tester) async {
        const summary = PickupReliabilitySummary(
          status: PickupReliabilityStatus.needsImprovement,
          reliabilityScore: 55.0,
          collectedOrders: 11,
          noShowOrders: 9,
          eligibleOrders: 20,
          recentEligibleOrders: 10,
          recentCollectedOrders: 6,
          recentNoShowOrders: 4,
          recentCollectionRate: 60.0,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PickupReliabilityCard(summary: summary)),
          ),
        );

        expect(
          find.text('Last 10 pickups: 6 collected · 4 missed'),
          findsOneWidget,
        );
        expect(
          find.textContaining("Great job — you've collected"),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Test 10 — New and insufficient-history users never get recent metrics',
      (tester) async {
        const summary = PickupReliabilitySummary(
          status: PickupReliabilityStatus.newUser,
          eligibleOrders: 0,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: PickupReliabilityCard(summary: summary)),
          ),
        );

        expect(find.textContaining('Last '), findsNothing);
        expect(find.textContaining("Great job"), findsNothing);
      },
    );
  });
}
