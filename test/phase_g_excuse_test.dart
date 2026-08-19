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
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/models/notification_model.dart';
import 'package:campusbite/models/order.dart';
import 'package:campusbite/widgets/no_show_notice.dart';

/// Phase G — ADMIN INTERVENTION (Excuse No-Show): student-facing contract.
///
/// The excuseNoShow callable marks a NO_SHOW order `noShowExcused: true`
/// while leaving `status` as `no_show`. These tests pin the student-side
/// display (excused notice), the FoodOrder parser, and the NO_SHOW_EXCUSED
/// notification type so the student sees that the missed pickup was excused
/// without any admin/private details leaking through.
void main() {
  group('Phase G — NoShowNotice excused variant', () {
    testWidgets('excused notice explains the reliability exclusion', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NoShowNotice(excused: true)),
        ),
      );

      expect(find.text('No-show excused'), findsOneWidget);
      expect(
        find.textContaining(
          'An administrator reviewed this order and excused the missed '
          'pickup.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('will not affect your pickup reliability'),
        findsOneWidget,
      );
      // No admin identity, private note, or strike language anywhere.
      expect(find.textContaining('admin1'), findsNothing);
      expect(find.textContaining('strike'), findsNothing);
    });

    testWidgets('unexcused notice keeps the standard wording', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NoShowNotice())),
      );

      expect(find.text('No-show recorded'), findsOneWidget);
      expect(find.textContaining('Order Missed'), findsOneWidget);
    });
  });

  group('Phase G — FoodOrder excuse fields', () {
    test('an excused no-show parses with status preserved as NO_SHOW', () async {
      final now = DateTime.now();
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('orders').doc('CB-excused-1');
      await ref.set({
        'studentId': 'user_1',
        'userName': 'Test Student',
        'items': [
          {
            'foodItemId': 'food_1',
            'title': 'Rice & Beans',
            'price': 3000.0,
            'quantity': 1,
            'image': '',
            'selectedCafe': 'Cafe A',
          },
        ],
        'price': 3000.0,
        'status': 'no_show',
        'createdAt': Timestamp.fromDate(now),
        'noShowAt': Timestamp.fromDate(now),
        'expiredAt': Timestamp.fromDate(now),
        'noShowExcused': true,
        'excusedAt': Timestamp.fromDate(now.add(const Duration(hours: 1))),
        'excusedBy': 'admin_1',
        'excuseReason': 'Student reported emergency',
        'excuseNote': null,
        'deadlineStatus': 'EXPIRED',
        'pickupWindowMinutes': 20,
      });

      final snapshot = await ref.get();
      final order = FoodOrder.fromFirestore(snapshot);

      expect(order.status, OrderStatus.noShow, reason: 'history is preserved');
      expect(order.noShowExcused, isTrue);
      expect(order.excusedAt, isNotNull);
      expect(order.excuseReason, 'Student reported emergency');
    });

    test('an unexcused no-show defaults to noShowExcused = false', () async {
      final now = DateTime.now();
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection('orders').doc('CB-unexcused-1');
      await ref.set({
        'studentId': 'user_1',
        'userName': 'Test Student',
        'items': [
          {
            'foodItemId': 'food_1',
            'title': 'Rice & Beans',
            'price': 3000.0,
            'quantity': 1,
            'image': '',
            'selectedCafe': 'Cafe A',
          },
        ],
        'price': 3000.0,
        'status': 'no_show',
        'createdAt': Timestamp.fromDate(now),
        'noShowAt': Timestamp.fromDate(now),
        'deadlineStatus': 'EXPIRED',
        'pickupWindowMinutes': 20,
      });

      final snapshot = await ref.get();
      final order = FoodOrder.fromFirestore(snapshot);

      expect(order.status, OrderStatus.noShow);
      expect(order.noShowExcused, isFalse);
      expect(order.excusedAt, isNull);
      expect(order.excuseReason, isNull);
    });
  });

  group('Phase G — NO_SHOW_EXCUSED notification type', () {
    test('round-trips through value and parse', () {
      expect(
        NotificationType.noShowExcused.value,
        'NO_SHOW_EXCUSED',
      );
      expect(
        NotificationType.fromString('NO_SHOW_EXCUSED'),
        NotificationType.noShowExcused,
      );
      expect(NotificationType.noShowExcused.label, 'Missed Pickup Excused');
    });
  });
}
