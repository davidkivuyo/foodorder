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
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../services/sync_queue_service.dart';

/// Banner widget that displays network status and sync recovery progress.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  final ConnectivityService _connectivity = ConnectivityService();
  final SyncQueueService _syncQueue = SyncQueueService();

  late bool _isOnline;
  late int _pendingCount;
  late bool _isSyncing;

  StreamSubscription<bool>? _connectivitySub;
  bool _showBackOnline = false;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _isOnline = _connectivity.isOnline;
    _pendingCount = _syncQueue.pendingCountNotifier.value;
    _isSyncing = _syncQueue.isSyncingNotifier.value;

    _connectivitySub = _connectivity.onConnectivityChanged.listen((online) {
      if (mounted) {
        setState(() {
          if (online && !_isOnline) {
            _showBackOnline = true;
            _dismissTimer?.cancel();
            _dismissTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _showBackOnline = false;
                });
              }
            });
          }
          _isOnline = online;
        });
      }
    });

    _syncQueue.pendingCountNotifier.addListener(_onPendingCountChanged);
    _syncQueue.isSyncingNotifier.addListener(_onSyncingChanged);
  }

  void _onPendingCountChanged() {
    if (mounted) {
      setState(() {
        _pendingCount = _syncQueue.pendingCountNotifier.value;
      });
    }
  }

  void _onSyncingChanged() {
    if (mounted) {
      setState(() {
        _isSyncing = _syncQueue.isSyncingNotifier.value;
      });
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _dismissTimer?.cancel();
    _syncQueue.pendingCountNotifier.removeListener(_onPendingCountChanged);
    _syncQueue.isSyncingNotifier.removeListener(_onSyncingChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isOnline && !_isSyncing && !_showBackOnline && _pendingCount == 0) {
      return const SizedBox.shrink();
    }

    Color bgColor;
    Widget icon;
    String message;

    if (!_isOnline) {
      bgColor = Colors.amber.shade900;
      icon = const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16);
      message = _pendingCount > 0
          ? 'Offline Mode • $_pendingCount queued action(s)'
          : 'Offline Mode • Changes will sync when online';
    } else if (_isSyncing) {
      bgColor = Colors.blue.shade800;
      icon = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
      message = 'Syncing queued actions...';
    } else if (_showBackOnline) {
      bgColor = Colors.green.shade800;
      icon = const Icon(Icons.check_circle_outline, color: Colors.white, size: 16);
      message = 'Back Online • Connectivity restored';
    } else if (_pendingCount > 0) {
      bgColor = Colors.indigo.shade800;
      icon = const Icon(Icons.sync_rounded, color: Colors.white, size: 16);
      message = '$_pendingCount pending sync action(s)';
    } else {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        bottom: false,
        top: false,
        child: Row(
          children: [
            icon,
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (_isOnline && !_isSyncing && _pendingCount > 0)
              GestureDetector(
                onTap: () => _syncQueue.processQueue(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Sync Now',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
