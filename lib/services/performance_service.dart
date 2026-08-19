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

import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Documented trace names — the only identifiers [startTrace] accepts.
const String kTraceMenuLoad = 'menu_load';
const String kTraceCheckout = 'checkout';
const String kTraceSearch = 'search';
const String kTraceUpdateCheck = 'update_check';

/// Allow-list of trace identifiers permitted by [PerformanceService.startTrace].
///
/// Any name outside this documented set is rejected, so personal or sensitive
/// values (UIDs, order IDs, search text, …) can never reach Firebase
/// Performance.
const Set<String> kApprovedTraceNames = {
  PerformanceService.appStartupTraceName,
  kTraceMenuLoad,
  kTraceCheckout,
  kTraceSearch,
  kTraceUpdateCheck,
};

/// Documented metric name for the menu-load trace: Firestore documents
/// received.
const String kMetricMenuLoadDocs = 'docs';

/// Allow-list of metric identifiers permitted by
/// [TraceHandle.incrementMetric]. Names outside this documented set are
/// rejected before reaching the SDK.
const Set<String> kApprovedMetricNames = {
  kMetricMenuLoadDocs,
};

/// Upper bound (inclusive) for metric values accepted by
/// [TraceHandle.incrementMetric] — guards against absurd or abusive counters.
const int kMaxMetricValue = 1000000;

/// Firebase Performance Monitoring (Phase 17 — Part 6).
///
/// Measures meaningful app flows: startup, menu load, search, checkout and
/// update check. Trace names are restricted to [kApprovedTraceNames] and
/// metric names to [kApprovedMetricNames] — no unnecessary custom traces are
/// created, and personal or sensitive identifiers can never reach Firebase
/// Performance.
///
/// Performance Monitoring is not supported on web; every call is a safe
/// no-op there and when initialization fails.
class PerformanceService {
  PerformanceService._();

  static final PerformanceService instance = PerformanceService._();

  bool _available = false;

  bool get isAvailable => _available;

  /// Trace name for cold-start measurement.
  static const String appStartupTraceName = 'app_startup';

  Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      // Explicitly enable collection (mirroring Analytics/Crashlytics). An
      // unlinked/disabled SDK throws here, which leaves availability off so
      // every trace call degrades to a safe no-op rather than a failure.
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);
      _available = true;
    } catch (_) {
      // Bare catch: Firebase access can throw non-Exception errors. Keep the
      // service unavailable — monitoring must never break the app.
    }
  }

  /// Test seam: when set, [startTrace] returns a fake handle instead of
  /// touching the Firebase Performance SDK. `null` restores production.
  TraceHandle? Function(String name)? _debugTraceFactory;

  /// Test seam: toggles availability so lifecycle behavior is testable
  /// without the Firebase SDK.
  @visibleForTesting
  void debugSetAvailable(bool value) => _available = value;

  /// Test seam: installs a fake trace factory (or restores production when
  /// `null`).
  @visibleForTesting
  void debugSetTraceFactory(TraceHandle? Function(String name)? factory) {
    _debugTraceFactory = factory;
  }

  /// Starts a named trace, or returns null when unavailable or when [name]
  /// is not in [kApprovedTraceNames].
  TraceHandle? startTrace(String name) {
    if (!_available) return null;
    // Privacy boundary: reject identifiers outside the documented allow-list
    // so sensitive values can never enter Firebase Performance.
    if (!kApprovedTraceNames.contains(name)) return null;
    final factory = _debugTraceFactory;
    if (factory != null) return factory(name);
    try {
      final trace = FirebasePerformance.instance.newTrace(name);
      // `start()` is async — consume its errors so a rejected platform
      // channel Future does not surface as an unhandled zone error.
      unawaited(trace.start().catchError((_) {}));
      return TraceHandle._(trace);
    } catch (_) {
      // Bare catch: Firebase access can throw non-Exception errors. Return
      // null so the trace degrades to a safe no-op rather than a failure.
      return null;
    }
  }

  TraceHandle? _startupTrace;

  /// Begins the app-startup measurement.
  ///
  /// Must be called only after [initialize] has completed — while the
  /// service is unavailable [startTrace] returns null and no trace is
  /// created. Callers invoke this before the first frame renders and pair it
  /// with [endAppStartup] after the first frame.
  void beginAppStartup() {
    _startupTrace = startTrace(appStartupTraceName);
  }

  /// Stops the app-startup measurement (call after the first frame).
  void endAppStartup() {
    _startupTrace?.stop();
    _startupTrace = null;
  }
}

/// Handle over an in-flight performance trace.
class TraceHandle {
  TraceHandle._(this._trace)
      : _onStop = null,
        _onIncrementMetric = null;

  /// Test handle that records lifecycle calls without a Firebase trace.
  @visibleForTesting
  TraceHandle.testing({
    required void Function() stopCallback,
    required void Function(String name, int value) incrementCallback,
  })  : _trace = null,
        _onStop = stopCallback,
        _onIncrementMetric = incrementCallback;

  final Trace? _trace;
  final void Function()? _onStop;
  final void Function(String name, int value)? _onIncrementMetric;

  void stop() {
    final trace = _trace;
    if (trace != null) {
      try {
        // `stop()` is async — consume its errors so a rejected platform
        // channel Future does not surface as an unhandled zone error.
        unawaited(trace.stop().catchError((_) {}));
      } catch (_) {
        // Bare catch: Firebase access can throw non-Exception errors.
      }
      return;
    }
    _onStop?.call();
  }

  void incrementMetric(String name, int value) {
    // Privacy boundary: only allow-listed metric names with sane, in-range
    // values reach the SDK.
    if (!kApprovedMetricNames.contains(name)) return;
    if (value < 0 || value > kMaxMetricValue) return;
    final trace = _trace;
    if (trace != null) {
      try {
        trace.incrementMetric(name, value);
      } catch (_) {
        // Bare catch: Firebase access can throw non-Exception errors.
      }
      return;
    }
    _onIncrementMetric?.call(name, value);
  }
}
