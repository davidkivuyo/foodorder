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

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_operation.dart';
import '../state/sync_queue_state.dart';
import 'connectivity_service.dart';

export '../state/sync_queue_state.dart'
    show SyncOperationHandler, CurrentUserIdProvider, kSyncQueueStorageKey, kMaxSyncRetries;

/// Stateless facade over [SyncQueueState].
///
/// Exposes the same public API as before but owns no mutable state itself:
/// the queue, handlers, persistence, notifiers and connectivity subscription
/// all live in [SyncQueueState], outside `lib/services/`.
class SyncQueueService {
  static final SyncQueueService _instance = SyncQueueService._internal();
  factory SyncQueueService() => _instance;

  final SyncQueueState _state;

  SyncQueueService._internal()
      : _state = SyncQueueState(connectivity: ConnectivityService().delegate);

  /// Testing constructor with injectable preferences and connectivity service.
  @visibleForTesting
  SyncQueueService.testing({
    required SharedPreferences prefs,
    ConnectivityService? connectivityService,
    CurrentUserIdProvider? currentUserIdProvider,
  }) : _state =
          // ignore: invalid_use_of_visible_for_testing_member
          SyncQueueState.testing(
            prefs: prefs,
            connectivity: connectivityService?.delegate,
            currentUserIdProvider: currentUserIdProvider,
          );

  Stream<String> get syncEvents => _state.syncEvents;
  List<SyncOperation> get queuedOperations => _state.queuedOperations;
  ValueNotifier<int> get pendingCountNotifier => _state.pendingCountNotifier;
  ValueNotifier<bool> get isSyncingNotifier => _state.isSyncingNotifier;

  /// Register an operation handler for a specific operation type.
  void registerHandler(String type, SyncOperationHandler handler) =>
      _state.registerHandler(type, handler);

  /// Enqueues a new offline operation and persists it to disk.
  Future<void> enqueue(SyncOperation op) => _state.enqueue(op);

  /// Removes an operation from the queue by ID.
  Future<void> removeOperation(String id) => _state.removeOperation(id);

  /// Clears all queued operations.
  Future<void> clearQueue() => _state.clearQueue();

  /// Processes all pending sync operations sequentially (FIFO).
  Future<void> processQueue() => _state.processQueue();

  void dispose() => _state.dispose();
}
