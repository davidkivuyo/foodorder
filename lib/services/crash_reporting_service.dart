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

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
// Imports error_service for ErrorCategory, which error_service itself
// imports back (for CrashReportingService.instance). The cycle is resolved
// at compile time — both singletons are lazy class statics, so there is no
// initialization-order hazard. Moving ErrorCategory to its own file would
// remove the cycle if it is ever refactored.
import 'error_service.dart' show ErrorCategory;
import 'logger_service.dart';
import 'platform_info.dart' show platformName, sdkVersion;

/// Custom-key names that may be attached to crash reports. Any other key is
/// rejected by [CrashReportingService.setCustomKey], so callers cannot attach
/// identifying or unexpected data.
const Set<String> kApprovedCrashKeys = {
  'app_version',
  'build_number',
  'platform',
  'sdk_version',
  'user_role',
  'screen',
  'network_status',
};

/// Crashlytics backend — swapped for a recording fake in tests.
@visibleForTesting
abstract class CrashlyticsBackend {
  Future<void> setCollectionEnabled(bool enabled);

  /// Records an error by [category] only — the raw exception message and any
  /// caller-supplied reason text never cross this boundary.
  Future<void> recordError(
    String category,
    StackTrace stack, {
    required bool fatal,
  });

  Future<void> log(String message);

  Future<void> setCustomKey(String key, String value);
}

/// Production backend backed by the Firebase Crashlytics SDK.
class _FirebaseCrashlyticsBackend implements CrashlyticsBackend {
  const _FirebaseCrashlyticsBackend();

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
  }

  @override
  Future<void> recordError(
    String category,
    StackTrace stack, {
    required bool fatal,
  }) {
    // Synthesize a non-identifying exception whose only content is the
    // category label — the SDK stringifies exception.toString()/reason into
    // the report, so the raw error text must never reach this call.
    return FirebaseCrashlytics.instance.recordError(
      StateError(category),
      stack,
      reason: category,
      fatal: fatal,
    );
  }

  @override
  Future<void> log(String message) {
    return FirebaseCrashlytics.instance.log(message);
  }

  @override
  Future<void> setCustomKey(String key, String value) {
    return FirebaseCrashlytics.instance.setCustomKey(key, value);
  }
}

/// Firebase Crashlytics integration (Phase 17 — Part 1).
///
/// Crash reports are anonymous: only non-identifying error categories and
/// allow-listed custom keys are recorded (app version, build number, SDK
/// version, platform, current screen, network status, user role). Raw
/// exception messages, reason text and FlutterErrorDetails are never sent.
/// Emails, UIDs, registration numbers, phone numbers, tokens and review text
/// are NEVER sent.
///
/// Crashlytics is not supported on web — every call is a safe no-op there
/// and when initialization fails, so monitoring can never break the app.
class CrashReportingService {
  CrashReportingService._([CrashlyticsBackend? backend])
      : _backend = backend ?? const _FirebaseCrashlyticsBackend();

  static final CrashReportingService instance = CrashReportingService._();

  CrashlyticsBackend _backend;
  bool _available = false;

  /// Whether Crashlytics is active on this platform/build.
  bool get isAvailable => _available;

  /// Test seam: installs a recording fake backend (or restores the Firebase
  /// backend when `null`). Resets availability so the next [initialize]
  /// uses the new backend.
  @visibleForTesting
  void debugSetBackend(CrashlyticsBackend? backend) {
    _backend = backend ?? const _FirebaseCrashlyticsBackend();
    _available = false;
  }

  /// Enables crash collection and records non-identifying app context keys.
  Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      await _backend.setCollectionEnabled(true);
      _available = true;
      _recordAppContext();
    } catch (e) {
      // Swallow every failure (including non-Exception errors when Firebase
      // is uninitialized) — monitoring must never break startup.
      LoggerService.instance.warning('Crashlytics init failed (${e.runtimeType})');
    }
  }

  /// Records the installed app version/build as Crashlytics custom keys.
  Future<void> recordAppVersion() async {
    if (!_available) return;
    try {
      final info = await PackageInfo.fromPlatform();
      setCustomKey('app_version', info.version);
      setCustomKey('build_number', info.buildNumber);
    } catch (_) {
      // Untyped catch (matching initialize): swallow every thrown value —
      // version keys are diagnostic aids, never required.
    }
  }

  /// Consumes a fire-and-forget backend future. Rejections (including
  /// non-Exception errors) are swallowed so monitoring never surfaces an
  /// unhandled async error; the surrounding try/catch still covers
  /// synchronous throws (e.g. an uninitialized Firebase getter).
  void _fire(Future<void> future) => unawaited(future.catchError((_) {}));

  void _recordAppContext() {
    if (!_available) return;
    try {
      _fire(_backend.setCustomKey('platform', platformName));
      _fire(_backend.setCustomKey('sdk_version', sdkVersion));
    } catch (_) {
      // Untyped catch (matching initialize): swallow every thrown value.
    }
  }

  /// Records a non-fatal (or fatal) error by [category] only. The raw
  /// exception and any reason text never reach Crashlytics.
  void recordError(
    ErrorCategory category,
    StackTrace stack, {
    bool fatal = false,
  }) {
    if (!_available) return;
    try {
      _fire(_backend.recordError(category.name, stack, fatal: fatal));
    } catch (_) {
      // Untyped catch (matching initialize): swallow every thrown value.
    }
  }

  /// Records a framework-level Flutter error by [category] only. This is an
  /// alias of [recordError] — the SDK's dedicated recordFlutterError path
  /// (which forwards FlutterErrorDetails context) is deliberately not used,
  /// so framework debugging context is traded away for the privacy boundary.
  void recordFlutterError(
    ErrorCategory category,
    StackTrace stack, {
    bool fatal = false,
  }) {
    recordError(category, stack, fatal: fatal);
  }

  /// Appends a sanitized breadcrumb to the next crash report.
  void log(String message) {
    if (!_available) return;
    try {
      _fire(_backend.log(LoggerService.sanitize(message)));
    } catch (_) {
      // Untyped catch (matching initialize): swallow every thrown value.
    }
  }

  /// User role only ('student' | 'admin' | 'guest') — never the UID.
  void setUserRole(String role) => setCustomKey('user_role', role);

  /// Current screen name only — never route arguments.
  void setCurrentScreen(String screen) => setCustomKey('screen', screen);

  void setNetworkStatus(bool online) =>
      setCustomKey('network_status', online ? 'online' : 'offline');

  /// Sets a custom key, ignoring any key outside [kApprovedCrashKeys].
  void setCustomKey(String key, String value) {
    if (!_available) return;
    if (!kApprovedCrashKeys.contains(key)) return;
    try {
      _fire(_backend.setCustomKey(key, LoggerService.sanitize(value)));
    } catch (_) {
      // Untyped catch (matching initialize): swallow every thrown value.
    }
  }
}
