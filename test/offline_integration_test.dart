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

import 'package:campusbite/models/sync_operation.dart';
import 'package:campusbite/services/connectivity_service.dart';
import 'package:campusbite/widgets/offline_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Offline Integration & UI Tests', () {
    testWidgets('OfflineBanner renders offline mode banner when offline', (tester) async {
      final connectivity = ConnectivityService.testing(initialOnline: false);
      ConnectivityService.setMockInstance(connectivity);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const OfflineBanner(),
                const Expanded(child: Text('Main App Content')),
              ],
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.textContaining('Offline Mode'), findsOneWidget);

      connectivity.setOnline(true);
      await tester.pump();
    });

    testWidgets('OfflineBanner hides when online and no pending items', (tester) async {
      final connectivity = ConnectivityService.testing(initialOnline: true);
      ConnectivityService.setMockInstance(connectivity);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                OfflineBanner(),
                Expanded(child: Text('Main Content')),
              ],
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.textContaining('Offline Mode'), findsNothing);
    });

    test('SyncOperation serialization integrity', () {
      final op = SyncOperation(
        id: 'sync-101',
        type: 'place_order',
        ownerUserId: 'student-42',
        payload: {'orderId': 'CB-1001', 'totalAmount': 45.0},
        timestamp: 1700000000000,
        retryCount: 2,
        status: SyncOperationStatus.pending,
        lastError: 'Timeout',
      );

      final jsonMap = op.toJson();
      final decoded = SyncOperation.fromJson(jsonMap);

      expect(decoded.id, equals(op.id));
      expect(decoded.type, equals(op.type));
      expect(decoded.ownerUserId, equals('student-42'));
      expect(decoded.payload['orderId'], equals('CB-1001'));
      expect(decoded.timestamp, equals(1700000000000));
      expect(decoded.retryCount, equals(2));
      expect(decoded.status, equals(SyncOperationStatus.pending));
      expect(decoded.lastError, equals('Timeout'));
    });
  });
}
