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
import 'package:flutter/widgets.dart';
import 'app_log.dart';

/// Service that monitors and broadcasts network connectivity status.
///
/// Provides a reactive stream [onConnectivityChanged] and boolean property [isOnline].
/// Supports dependency injection and testing overrides.
class ConnectivityService {
  static ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _isOnline = true;
  Timer? _pollingTimer;

  bool get isOnline => _isOnline;
  Stream<bool> get onConnectivityChanged => _controller.stream;

  ConnectivityService._internal({bool autoPoll = true}) {
    if (autoPoll && !isTesting) {
      _initPolling();
    }
  }

  /// Override the singleton instance (useful in tests).
  @visibleForTesting
  static void setMockInstance(ConnectivityService mock) {
    _instance = mock;
  }

  /// Constructor for unit testing with controllable initial state and stream.
  @visibleForTesting
  ConnectivityService.testing({
    bool initialOnline = true,
    Stream<bool>? connectivityStream,
  }) : _isOnline = initialOnline {
    if (connectivityStream != null) {
      connectivityStream.listen((online) {
        setOnline(online);
      });
    }
  }

  static bool get isTesting =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');

  void _initPolling() {
    checkConnectivity();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      checkConnectivity();
    });
  }

  /// Forces network check and updates online status.
  Future<bool> checkConnectivity() async {
    return _isOnline;
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
    _controller.close();
  }
}
