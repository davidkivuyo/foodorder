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
import 'package:flutter/foundation.dart';
import '../services/connectivity_service.dart';
import '../services/sync_queue_service.dart';

/// ViewModel for [OfflineBanner].
///
/// Owns all connectivity/sync business logic: subscribes to the
/// connectivity and sync-queue services, drives the "Back Online"
/// auto-dismiss timer, and exposes a plain state surface for the view
/// to render.
class OfflineBannerViewModel extends ChangeNotifier {
  OfflineBannerViewModel({
    ConnectivityService? connectivityService,
    SyncQueueService? syncQueueService,
  })  : _connectivity = connectivityService ?? ConnectivityService(),
        _syncQueue = syncQueueService ?? SyncQueueService() {
    _isOnline = _connectivity.isOnline;
    _pendingCount = _syncQueue.pendingCountNotifier.value;
    _isSyncing = _syncQueue.isSyncingNotifier.value;

    _connectivitySub =
        _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    _syncQueue.pendingCountNotifier.addListener(_onPendingCountChanged);
    _syncQueue.isSyncingNotifier.addListener(_onSyncingChanged);
  }

  final ConnectivityService _connectivity;
  final SyncQueueService _syncQueue;

  late bool _isOnline;
  late int _pendingCount;
  late bool _isSyncing;
  bool _showBackOnline = false;

  StreamSubscription<bool>? _connectivitySub;
  Timer? _dismissTimer;

  bool get isOnline => _isOnline;
  int get pendingCount => _pendingCount;
  bool get isSyncing => _isSyncing;
  bool get showBackOnline => _showBackOnline;

  /// True when nothing needs to be shown.
  bool get isHidden =>
      _isOnline && !_isSyncing && !_showBackOnline && _pendingCount == 0;

  /// True when the "Sync Now" affordance should be available.
  bool get canSyncNow => _isOnline && !_isSyncing && _pendingCount > 0;

  void _onConnectivityChanged(bool online) {
    if (online && !_isOnline) {
      _showBackOnline = true;
      _dismissTimer?.cancel();
      _dismissTimer = Timer(const Duration(seconds: 3), () {
        _showBackOnline = false;
        notifyListeners();
      });
    }
    _isOnline = online;
    notifyListeners();
  }

  void _onPendingCountChanged() {
    _pendingCount = _syncQueue.pendingCountNotifier.value;
    notifyListeners();
  }

  void _onSyncingChanged() {
    _isSyncing = _syncQueue.isSyncingNotifier.value;
    notifyListeners();
  }

  /// Trigger a manual sync of queued offline operations.
  Future<void> syncNow() => _syncQueue.processQueue();

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _dismissTimer?.cancel();
    _syncQueue.pendingCountNotifier.removeListener(_onPendingCountChanged);
    _syncQueue.isSyncingNotifier.removeListener(_onSyncingChanged);
    super.dispose();
  }
}
