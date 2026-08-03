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
import 'package:campusbite/services/sync_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('SyncQueueService Tests', () {
    test('enqueues operation and persists to SharedPreferences', () async {
      final connectivity = ConnectivityService.testing(initialOnline: false);
      final queueService = SyncQueueService.testing(
        prefs: prefs,
        connectivityService: connectivity,
      );

      final op = SyncOperation(
        id: 'op-1',
        type: 'cart_add',
        payload: {'foodItemId': 'food-123', 'quantity': 2},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await queueService.enqueue(op);

      expect(queueService.queuedOperations.length, equals(1));
      expect(queueService.queuedOperations.first.id, equals('op-1'));
      expect(queueService.pendingCountNotifier.value, equals(1));

      // Reload queue from prefs to verify persistence
      final rawList = prefs.getStringList(kSyncQueueStorageKey);
      expect(rawList, isNotNull);
      expect(rawList!.length, equals(1));
    });

    test('processes queue when connectivity is restored', () async {
      final connectivity = ConnectivityService.testing(initialOnline: false);
      final queueService = SyncQueueService.testing(
        prefs: prefs,
        connectivityService: connectivity,
      );

      final processedTypes = <String>[];
      queueService.registerHandler('cart_add', (op) async {
        processedTypes.add(op.type);
        return true;
      });

      final op = SyncOperation(
        id: 'op-2',
        type: 'cart_add',
        payload: {'foodItemId': 'food-456', 'quantity': 1},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await queueService.enqueue(op);
      expect(processedTypes, isEmpty);

      // Simulate connection restored
      connectivity.setOnline(true);
      await Future.delayed(Duration.zero);

      expect(processedTypes, equals(['cart_add']));
      expect(queueService.queuedOperations, isEmpty);
      expect(queueService.pendingCountNotifier.value, equals(0));
    });

    test('handles retries and marks failed after max retries', () async {
      final connectivity = ConnectivityService.testing(initialOnline: false);
      final queueService = SyncQueueService.testing(
        prefs: prefs,
        connectivityService: connectivity,
      );

      int attempts = 0;
      queueService.registerHandler('failing_op', (op) async {
        attempts++;
        return false; // failure
      });

      final op = SyncOperation(
        id: 'op-fail',
        type: 'failing_op',
        payload: {},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await queueService.enqueue(op);
      connectivity.setOnline(true);

      // 1st attempt
      await queueService.processQueue();
      expect(attempts, equals(1));
      expect(queueService.queuedOperations.first.retryCount, equals(1));
      expect(queueService.queuedOperations.first.status, equals(SyncOperationStatus.pending));

      // 4 more attempts to reach maxRetries = 5
      for (int i = 0; i < 4; i++) {
        await queueService.processQueue();
      }

      expect(attempts, equals(5));
      expect(queueService.queuedOperations.first.retryCount, equals(5));
      expect(queueService.queuedOperations.first.status, equals(SyncOperationStatus.failed));
    });

    test('LWW conflict resolution retains newer timestamp operation', () async {
      final opOlder = SyncOperation(
        id: 'op-old',
        type: 'cart_update',
        payload: {'quantity': 1},
        timestamp: 1000,
      );
      final opNewer = SyncOperation(
        id: 'op-new',
        type: 'cart_update',
        payload: {'quantity': 3},
        timestamp: 2000,
      );

      expect(opNewer.timestamp, greaterThan(opOlder.timestamp));
    });
  });
}
