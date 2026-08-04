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

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_operation.dart';
import '../services/app_log.dart';
import 'connectivity_state.dart';

typedef SyncOperationHandler = Future<bool> Function(SyncOperation op);

/// Resolves the UID of the currently authenticated user (or null).
typedef CurrentUserIdProvider = String? Function();

/// Default provider backed by Firebase Auth.
String? _authCurrentUserId() => FirebaseAuth.instance.currentUser?.uid;

/// Key used to store queued sync operations in SharedPreferences.
const String kSyncQueueStorageKey = 'campusbite_sync_queue';
const int kMaxSyncRetries = 5;

/// Owns the mutable offline-sync state for the app.
///
/// The long-lived pieces of [SyncQueueService] — the queued operations,
/// registered handlers, SharedPreferences persistence, notifiers and the
/// connectivity subscription — live here, outside `lib/services/`, so service
/// classes stay stateless facades.
class SyncQueueState {
  SyncQueueState({ConnectivityState? connectivity})
      : _connectivity = connectivity ?? ConnectivityState(),
        _currentUserIdProvider = _authCurrentUserId {
    _init();
  }

  /// Testing constructor with injectable preferences and connectivity state.
  @visibleForTesting
  SyncQueueState.testing({
    required SharedPreferences prefs,
    ConnectivityState? connectivity,
    CurrentUserIdProvider? currentUserIdProvider,
  })  :
        // ignore: prefer_initializing_formals
        _prefs = prefs,
        // ignore: invalid_use_of_visible_for_testing_member
        _connectivity = connectivity ?? ConnectivityState.testing(),
        _currentUserIdProvider = currentUserIdProvider ?? _authCurrentUserId {
    _loadQueueFromPrefs();
    _listenConnectivity();
    _initCompleter.complete();
  }

  final ConnectivityState _connectivity;
  final CurrentUserIdProvider _currentUserIdProvider;
  SharedPreferences? _prefs;
  StreamSubscription<bool>? _connectivitySub;

  final Map<String, SyncOperationHandler> _handlers = {};
  final List<SyncOperation> _queue = [];

  /// Completes once [_init] has finished loading persisted operations,
  /// so no mutating method can touch [_queue] or [SharedPreferences]
  /// before the persisted queue has been fully loaded.
  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get _whenInitialized => _initCompleter.future;

  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);
  final StreamController<String> _syncEventsController = StreamController<String>.broadcast();

  Stream<String> get syncEvents => _syncEventsController.stream;
  List<SyncOperation> get queuedOperations => List.unmodifiable(_queue);

  Future<void> _init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadQueueFromPrefs();
      _listenConnectivity();
    } on Exception catch (e, stack) {
      AppLog.e('[SyncQueueService] Init error', e, stack);
    } finally {
      // Always release waiters so an init failure degrades to an
      // in-memory-only queue instead of hanging every mutating call.
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    }
  }

  void _listenConnectivity() {
    _connectivitySub?.cancel();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        AppLog.d('[SyncQueueService] Connection restored - triggering sync recovery');
        processQueue();
      }
    });
  }

  Future<void> _loadQueueFromPrefs() async {
    final prefs = _prefs;
    if (prefs == null) return;

    final rawList = prefs.getStringList(kSyncQueueStorageKey) ?? [];
    _queue.clear();
    for (final jsonStr in rawList) {
      try {
        _queue.add(SyncOperation.decode(jsonStr));
      } on Exception catch (e) {
        AppLog.e('[SyncQueueService] Failed to parse operation from prefs', e);
      }
    }
    _updatePendingNotifier();
  }

  Future<void> _saveQueueToPrefs() async {
    final prefs = _prefs;
    if (prefs == null) return;

    final rawList = _queue.map((op) => op.encode()).toList();
    await prefs.setStringList(kSyncQueueStorageKey, rawList);
    _updatePendingNotifier();
  }

  void _updatePendingNotifier() {
    pendingCountNotifier.value = _queue
        .where((op) => op.status == SyncOperationStatus.pending || op.status == SyncOperationStatus.syncing)
        .length;
  }

  /// Register an operation handler for a specific operation type.
  void registerHandler(String type, SyncOperationHandler handler) {
    _handlers[type] = handler;
  }

  /// Enqueues a new offline operation and persists it to disk.
  Future<void> enqueue(SyncOperation op) async {
    await _whenInitialized;
    _queue.add(op);
    await _saveQueueToPrefs();
    AppLog.d('[SyncQueueService] Enqueued operation ${op.id} of type ${op.type}');

    if (_connectivity.isOnline) {
      processQueue();
    }
  }

  /// Removes an operation from the queue by ID.
  Future<void> removeOperation(String id) async {
    await _whenInitialized;
    _queue.removeWhere((op) => op.id == id);
    await _saveQueueToPrefs();
  }

  /// Clears all queued operations.
  Future<void> clearQueue() async {
    await _whenInitialized;
    _queue.clear();
    await _saveQueueToPrefs();
  }

  /// Processes all pending sync operations sequentially (FIFO).
  Future<void> processQueue() async {
    await _whenInitialized;
    if (isSyncingNotifier.value) return; // Prevent concurrent processing runs
    if (_queue.isEmpty) return;
    if (!_connectivity.isOnline) return;

    isSyncingNotifier.value = true;
    _syncEventsController.add('Sync starting');
    AppLog.d('[SyncQueueService] Starting sync recovery for ${_queue.length} items');

    final pendingOps = List<SyncOperation>.from(
      _queue.where((op) => op.status == SyncOperationStatus.pending || op.status == SyncOperationStatus.syncing),
    )..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    int successCount = 0;

    for (final op in pendingOps) {
      if (!_connectivity.isOnline) {
        AppLog.w('[SyncQueueService] Connection lost mid-sync. Pausing queue.');
        break;
      }

      // ── Ownership guard ──────────────────────────────────────────────
      // Never replay an operation for a user other than the currently
      // authenticated one. Handlers write to `users/{currentUserId}` on
      // replay, so replaying a stale operation after an account switch
      // would mutate another user's data. Unverifiable (legacy) operations
      // are discarded with an explicit error state instead of replayed.
      final currentUserId = _currentUserIdProvider();
      if (op.ownerUserId == null || op.ownerUserId != currentUserId) {
        final reason = op.ownerUserId == null
            ? 'Operation has no owner — not replayed'
            : 'User mismatch — operation not replayed';
        AppLog.w('[SyncQueueService] Skipping operation ${op.id}: $reason');
        AppLog.d(
          '[SyncQueueService] Skipping ${op.id}: owner=${op.ownerUserId}, '
          'current=$currentUserId',
        );
        final idx = _queue.indexWhere((item) => item.id == op.id);
        if (idx != -1) {
          _queue[idx] = op.copyWith(
            status: SyncOperationStatus.failed,
            lastError: reason,
          );
          await _saveQueueToPrefs();
        }
        continue;
      }

      final handler = _handlers[op.type];
      if (handler == null) {
        AppLog.e('[SyncQueueService] No registered handler for operation type ${op.type}');
        final idx = _queue.indexWhere((item) => item.id == op.id);
        if (idx != -1) {
          _queue[idx] = op.copyWith(
            status: SyncOperationStatus.failed,
            lastError: 'No registered handler',
          );
          await _saveQueueToPrefs();
        }
        continue;
      }

      final opIndex = _queue.indexWhere((item) => item.id == op.id);
      if (opIndex != -1) {
        _queue[opIndex] = op.copyWith(status: SyncOperationStatus.syncing);
        await _saveQueueToPrefs();
      }

      try {
        final success = await handler(op);
        if (success) {
          _queue.removeWhere((item) => item.id == op.id);
          await _saveQueueToPrefs();
          successCount++;
          AppLog.d('[SyncQueueService] Successfully synced operation ${op.id}');
        } else {
          _handleOpFailure(op, 'Handler returned false');
        }
      } on Exception catch (e) {
        _handleOpFailure(op, e.toString());
      }
    }

    isSyncingNotifier.value = false;
    if (successCount > 0) {
      _syncEventsController.add('$successCount operations synced');
    }
  }

  void _handleOpFailure(SyncOperation op, String error) {
    final idx = _queue.indexWhere((item) => item.id == op.id);
    if (idx == -1) return;

    final newRetry = op.retryCount + 1;
    final isMax = newRetry >= kMaxSyncRetries;
    _queue[idx] = op.copyWith(
      retryCount: newRetry,
      status: isMax ? SyncOperationStatus.failed : SyncOperationStatus.pending,
      lastError: error,
    );
    _saveQueueToPrefs();
    AppLog.w('[SyncQueueService] Operation ${op.id} failed (attempt $newRetry/$kMaxSyncRetries)');
    AppLog.d('[SyncQueueService] Operation ${op.id} failure detail: $error');
  }

  void dispose() {
    _connectivitySub?.cancel();
    _syncEventsController.close();
    pendingCountNotifier.dispose();
    isSyncingNotifier.dispose();
  }
}
