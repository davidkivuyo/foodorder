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

import 'analytics_service.dart' show AnalyticsBackend;

/// Mutable analytics runtime state, extracted from [AnalyticsService] so the
/// service stays a stateless facade.
///
/// Owns the backend reference, the availability flag, the initialization
/// marker and the bounded re-initialization timer. On retry it invokes the
/// bound [onRetry] callback (the service's `initialize()`), keeping all
/// retained mutable state — and the retry scheduling — inside this state
/// holder instead of the service.
class AnalyticsRuntime {
  AnalyticsRuntime(AnalyticsBackend backend) : _backend = backend;

  AnalyticsBackend _backend;
  bool _available = false;
  bool _initialized = false;
  Timer? _retryTimer;
  int _retryAttempts = 0;
  Future<void> Function()? _onRetry;

  /// Upper bound on re-initialization attempts so recovery never becomes
  /// continuous polling. Once exceeded, analytics stays unavailable until the
  /// next app launch.
  static const int _maxRetryAttempts = 3;
  static const Duration _retryDelay = Duration(seconds: 30);

  /// The active analytics backend.
  AnalyticsBackend get backend => _backend;

  bool get isAvailable => _available;

  /// Binds the re-initialization action fired by a scheduled retry.
  void bindRetry(Future<void> Function() onRetry) => _onRetry = onRetry;

  /// Swaps the backend and resets all runtime state (test seam).
  void setBackend(AnalyticsBackend backend) {
    _backend = backend;
    reset();
  }

  /// Marks that bootstrapping was attempted, enabling later retries.
  void markInitializing() => _initialized = true;

  /// Marks analytics as usable and clears any pending retry state.
  void markAvailable() {
    _available = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempts = 0;
  }

  /// Marks analytics as unusable (e.g. after a backend logging failure).
  void markUnavailable() => _available = false;

  /// Schedules a single bounded re-initialization attempt. Guarded so at most
  /// one timer is ever pending and the total number of attempts is capped —
  /// no continuous polling or unbounded scheduling. No-op when bootstrapping
  /// was never attempted, when already available, when the cap is reached, or
  /// when no retry action is bound.
  void scheduleRetryIfBootstrapped() {
    if (!_initialized || _available || _retryTimer != null) return;
    if (_retryAttempts >= _maxRetryAttempts) return;
    final onRetry = _onRetry;
    if (onRetry == null) return;
    _retryAttempts++;
    _retryTimer = Timer(_retryDelay, () {
      _retryTimer = null;
      onRetry();
    });
  }

  /// Resets all runtime state (used by the test backend seam and on a fresh
  /// app launch).
  void reset() {
    _available = false;
    _initialized = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempts = 0;
  }
}
