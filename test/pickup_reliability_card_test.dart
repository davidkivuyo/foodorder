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
      'Test 4 — Poor status renders non-punitive constructive reminder',
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
  });
}
