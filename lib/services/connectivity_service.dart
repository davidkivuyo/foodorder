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
import '../state/connectivity_state.dart';

/// Stateless facade over [ConnectivityState].
///
/// Exposes the same public API as before but owns no mutable state itself:
/// the online status, broadcast stream and polling timer all live in
/// [ConnectivityState], outside `lib/services/`.
class ConnectivityService {
  static ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;

  final ConnectivityState _state;

  ConnectivityService._internal() : _state = ConnectivityState();

  /// Constructor for unit testing with controllable initial state and stream.
  @visibleForTesting
  ConnectivityService.testing({
    bool initialOnline = true,
    Stream<bool>? connectivityStream,
  }) : _state =
          // ignore: invalid_use_of_visible_for_testing_member
          ConnectivityState.testing(
            initialOnline: initialOnline,
            connectivityStream: connectivityStream,
          );

  /// The mutable state this facade delegates to.
  ///
  /// Shared across the app so a single connectivity source of truth drives
  /// every consumer (widgets, cart, and the sync queue).
  ConnectivityState get delegate => _state;

  /// Override the singleton instance (useful in tests).
  @visibleForTesting
  static void setMockInstance(ConnectivityService mock) {
    _instance = mock;
  }

  bool get isOnline => _state.isOnline;
  Stream<bool> get onConnectivityChanged => _state.onConnectivityChanged;

  /// Forces network check and updates online status.
  Future<bool> checkConnectivity() => _state.checkConnectivity();

  /// Manually update online status (used by test setup or network listeners).
  void setOnline(bool online) => _state.setOnline(online);

  void dispose() => _state.dispose();
}
