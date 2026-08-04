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
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import '../services/app_log.dart';

/// Owns the mutable network-connectivity state for the app.
///
/// The long-lived pieces of [ConnectivityService] — the current online
/// status, the broadcast stream, the platform connectivity listener and the
/// polling timer — live here, outside `lib/services/`, so service classes
/// stay stateless facades.
///
/// Connectivity is derived from the real platform signal: a
/// [Connectivity.onConnectivityChanged] listener plus periodic
/// [checkConnectivity] probes, both of which publish results via [setOnline].
class ConnectivityState {
  ConnectivityState({bool autoPoll = true}) {
    if (autoPoll && !isTesting) {
      _listenPlatformChanges();
      _initPolling();
    }
  }

  /// Constructor for unit testing with controllable initial state and stream.
  @visibleForTesting
  ConnectivityState.testing({
    bool initialOnline = true,
    Stream<bool>? connectivityStream,
  }) : _isOnline = initialOnline {
    if (connectivityStream != null) {
      connectivityStream.listen((online) {
        setOnline(online);
      });
    }
  }

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  final Connectivity _connectivity = Connectivity();
  bool _isOnline = true;
  Timer? _pollingTimer;
  StreamSubscription<List<ConnectivityResult>>? _platformSub;

  bool get isOnline => _isOnline;
  Stream<bool> get onConnectivityChanged => _controller.stream;

  static bool get isTesting =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');

  void _listenPlatformChanges() {
    _platformSub = _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((result) => result != ConnectivityResult.none);
      AppLog.d('[ConnectivityService] Platform connectivity report: online=$online');
      setOnline(online);
    });
  }

  void _initPolling() {
    checkConnectivity();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      checkConnectivity();
    });
  }

  /// Performs a real platform connectivity check and publishes the result.
  ///
  /// Always resolves to a boolean; a platform error degrades to the last
  /// known state instead of surfacing.
  Future<bool> checkConnectivity() async {
    bool online;
    try {
      final results = await _connectivity.checkConnectivity();
      online = results.any((result) => result != ConnectivityResult.none);
    } on Exception catch (e) {
      AppLog.d('[ConnectivityService] Connectivity check failed: $e');
      online = _isOnline;
    }
    setOnline(online);
    return online;
  }

  /// Manually update online status (used by test setup or network listeners).
  void setOnline(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      AppLog.d('[ConnectivityService] Connectivity state changed: online=$online');
      _controller.add(online);
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
    _platformSub?.cancel();
    _controller.close();
  }
}
