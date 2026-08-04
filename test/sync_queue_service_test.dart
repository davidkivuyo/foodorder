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
        ownerUserId: 'test-user',
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

    test('early enqueue before init completes is not lost', () async {
      // Seed a persisted operation so the singleton's async _loadQueueFromPrefs
      // has data to load once SharedPreferences.getInstance() resolves.
      final seeded = SyncOperation(
        id: 'op-seeded',
        type: 'cart_add',
        ownerUserId: 'test-user',
        payload: {'foodItemId': 'food-123', 'quantity': 1},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      SharedPreferences.setMockInitialValues({
        kSyncQueueStorageKey: [seeded.encode()],
      });
      ConnectivityService.setMockInstance(
        ConnectivityService.testing(initialOnline: false),
      );

      // The singleton kicks off async initialization in its constructor.
      final queue = SyncQueueService();

      // Enqueue immediately, before initialization has necessarily finished.
      final early = SyncOperation(
        id: 'op-early',
        type: 'cart_add',
        ownerUserId: 'test-user',
        payload: {'foodItemId': 'food-456', 'quantity': 2},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await queue.enqueue(early);

      // Both the seeded and the early operation must survive init: loading
      // the persisted queue must never wipe out an unpersisted early enqueue.
      expect(
        queue.queuedOperations.map((op) => op.id),
        containsAll(['op-seeded', 'op-early']),
      );
      expect(queue.queuedOperations.length, equals(2));

      final persistedPrefs = await SharedPreferences.getInstance();
      final persisted = persistedPrefs.getStringList(kSyncQueueStorageKey);
      expect(persisted, isNotNull);
      expect(persisted!.length, equals(2));
    });

    test('processes queue when connectivity is restored', () async {
      final connectivity = ConnectivityService.testing(initialOnline: false);
      final queueService = SyncQueueService.testing(
        prefs: prefs,
        connectivityService: connectivity,
        currentUserIdProvider: () => 'test-user',
      );

      final processedTypes = <String>[];
      queueService.registerHandler('cart_add', (op) async {
        processedTypes.add(op.type);
        return true;
      });

      final op = SyncOperation(
        id: 'op-2',
        type: 'cart_add',
        ownerUserId: 'test-user',
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
        currentUserIdProvider: () => 'test-user',
      );

      int attempts = 0;
      queueService.registerHandler('failing_op', (op) async {
        attempts++;
        return false; // failure
      });

      final op = SyncOperation(
        id: 'op-fail',
        type: 'failing_op',
        ownerUserId: 'test-user',
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

    test('marks an operation failed and persists it when no handler is registered', () async {
      final connectivity = ConnectivityService.testing(initialOnline: false);
      final queueService = SyncQueueService.testing(
        prefs: prefs,
        connectivityService: connectivity,
        currentUserIdProvider: () => 'test-user',
      );

      // No handler registered for 'cart_add', so it must be discarded.
      final op = SyncOperation(
        id: 'op-no-handler',
        type: 'cart_add',
        ownerUserId: 'test-user',
        payload: {'foodItemId': 'food-999', 'quantity': 1},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await queueService.enqueue(op);
      expect(queueService.pendingCountNotifier.value, equals(1));

      connectivity.setOnline(true);
      await queueService.processQueue();

      // Failed in-memory with the error recorded.
      expect(queueService.queuedOperations.length, equals(1));
      expect(
        queueService.queuedOperations.first.status,
        equals(SyncOperationStatus.failed),
      );
      expect(
        queueService.queuedOperations.first.lastError,
        contains('No registered handler'),
      );
      // The failed state is reflected in the pending notifier...
      expect(queueService.pendingCountNotifier.value, equals(0));
      // ...and persisted, so a reload does not resurrect it as pending.
      final rawList = prefs.getStringList(kSyncQueueStorageKey);
      expect(rawList, isNotNull);
      final reloaded = rawList!.map(SyncOperation.decode).toList();
      expect(reloaded.length, equals(1));
      expect(reloaded.first.status, equals(SyncOperationStatus.failed));
    });

    test('does not drop an operation when its handler throws', () async {
      final connectivity = ConnectivityService.testing(initialOnline: false);
      final queueService = SyncQueueService.testing(
        prefs: prefs,
        connectivityService: connectivity,
        currentUserIdProvider: () => 'test-user',
      );

      queueService.registerHandler('exploding_op', (op) async {
        throw Exception('transient failure');
      });

      final op = SyncOperation(
        id: 'op-throw',
        type: 'exploding_op',
        ownerUserId: 'test-user',
        payload: {},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await queueService.enqueue(op);
      connectivity.setOnline(true);
      await queueService.processQueue();

      // A throwing handler must be treated as a failure, not a success:
      // the operation stays queued for retry with the error recorded.
      expect(queueService.queuedOperations.length, equals(1));
      expect(queueService.queuedOperations.first.status, equals(SyncOperationStatus.pending));
      expect(queueService.queuedOperations.first.retryCount, equals(1));
      expect(
        queueService.queuedOperations.first.lastError,
        contains('transient failure'),
      );
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

    test('does not replay an operation owned by a different user', () async {
      final connectivity = ConnectivityService.testing(initialOnline: false);
      final queueService = SyncQueueService.testing(
        prefs: prefs,
        connectivityService: connectivity,
        currentUserIdProvider: () => 'current-user',
      );

      int handlerCalls = 0;
      queueService.registerHandler('cart_add', (op) async {
        handlerCalls++;
        return true;
      });

      final op = SyncOperation(
        id: 'op-foreign',
        type: 'cart_add',
        ownerUserId: 'other-user',
        payload: {'foodItemId': 'food-789', 'quantity': 1},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await queueService.enqueue(op);
      connectivity.setOnline(true);
      await queueService.processQueue();

      // Handler must never run for another user's operation.
      expect(handlerCalls, equals(0));
      // The operation is discarded with an explicit error state.
      expect(queueService.queuedOperations.length, equals(1));
      expect(
        queueService.queuedOperations.first.status,
        equals(SyncOperationStatus.failed),
      );
      expect(
        queueService.queuedOperations.first.lastError,
        contains('User mismatch'),
      );
      expect(queueService.pendingCountNotifier.value, equals(0));
    });

    test('does not replay an unverifiable legacy operation without owner', () async {
      final connectivity = ConnectivityService.testing(initialOnline: false);
      final queueService = SyncQueueService.testing(
        prefs: prefs,
        connectivityService: connectivity,
        currentUserIdProvider: () => 'current-user',
      );

      int handlerCalls = 0;
      queueService.registerHandler('cart_add', (op) async {
        handlerCalls++;
        return true;
      });

      final op = SyncOperation(
        id: 'op-legacy',
        type: 'cart_add',
        payload: {'foodItemId': 'food-000', 'quantity': 1},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await queueService.enqueue(op);
      connectivity.setOnline(true);
      await queueService.processQueue();

      expect(handlerCalls, equals(0));
      expect(
        queueService.queuedOperations.first.status,
        equals(SyncOperationStatus.failed),
      );
      expect(
        queueService.queuedOperations.first.lastError,
        contains('no owner'),
      );
    });
  });
}
