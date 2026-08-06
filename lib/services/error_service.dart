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

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'analytics_service.dart';
import 'crash_reporting_service.dart';
import 'logger_service.dart';

/// Coarse categorization of an error (Phase 17 — Part 2).
enum ErrorCategory {
  network,
  timeout,
  permission,
  server,
  quota,
  validation,
  auth,
  storage,
  unknown,
}

/// Centralized error handling (Phase 17 — Parts 2, 3, 8, 9, 10).
///
/// Every uncaught exception passes through this service: it logs locally,
/// forwards to Crashlytics and Analytics, categorizes the error, and maps
/// technical exceptions to user-friendly messages. It never allows an
/// uncaught exception to surface internal details to the user.
class ErrorService {
  ErrorService._();

  static final ErrorService instance = ErrorService._();

  /// Installs the global Flutter/zone error handlers. Call once at startup.
  void init() {
    FlutterError.onError = (details) => handleFlutterError(details);
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      handleZoneError(error, stack);
      return true; // handled — do not terminate the isolate
    };
  }

  /// Handles errors caught by `runZonedGuarded` (async zone errors).
  void handleZoneError(Object error, StackTrace stack) {
    LoggerService.instance.error('Uncaught async error', error, stack);
    CrashReportingService.instance.recordError(categorize(error), stack);
  }

  /// Handles Flutter framework errors (build/layout/rendering).
  void handleFlutterError(FlutterErrorDetails details) {
    LoggerService.instance.error(
      'Flutter framework error',
      details.exception,
      details.stack,
    );
    CrashReportingService.instance.recordFlutterError(
      categorize(details.exception),
      details.stack ?? StackTrace.current,
    );
    AnalyticsService.instance.logEvent(
      AnalyticsEvent.errorOccurred,
      params: {'error_type': categorize(details.exception).name},
    );
  }

  /// Records a Firestore failure as a summary only (Phase 17 — Part 8).
  /// Never creates Firestore documents for errors.
  void recordFirestoreError(Object error) {
    final category = categorize(error);
    LoggerService.instance.warning(
      'Firestore error (${category.name}): ${_bareCode(error)}',
    );
    AnalyticsService.instance.logEvent(
      AnalyticsEvent.firestoreError,
      params: {'error_type': category.name},
    );
    CrashReportingService.instance.log('firestore error: ${category.name}');
  }

  /// Records a client-side Cloud Function call failure (Phase 17 — Part 9).
  /// Cloud Functions themselves own their server logs.
  void recordFunctionError(Object error) {
    final category = categorize(error);
    LoggerService.instance.warning(
      'Cloud Function call failed (${category.name})',
    );
    CrashReportingService.instance.log('function error: ${category.name}');
  }

  ErrorCategory categorize(Object error) {
    if (error is TimeoutException) return ErrorCategory.timeout;
    if (error is http.ClientException) return ErrorCategory.network;
    if (error is FirebaseException) {
      final code = _bareCode(error);
      switch (code) {
        case 'permission-denied':
          return ErrorCategory.permission;
        case 'resource-exhausted':
        case 'quota-exceeded':
        case 'quota':
          return ErrorCategory.quota;
        case 'unavailable':
        case 'aborted':
        case 'internal':
          return ErrorCategory.server;
        case 'network-request-failed':
        case 'channel-error':
          return ErrorCategory.network;
        case 'invalid-argument':
        case 'invalid-email':
        case 'failed-precondition':
          return ErrorCategory.validation;
        case 'not-found':
        case 'already-exists':
          return ErrorCategory.storage;
      }
    }
    if (error is PlatformException) {
      final code = _bareCode(error);
      if (code == 'network-request-failed' ||
          code == 'channel-error' ||
          code == 'connection-error') {
        return ErrorCategory.network;
      }
      if (code == 'permission-denied') return ErrorCategory.permission;
    }
    if (error is FormatException) return ErrorCategory.validation;
    return ErrorCategory.unknown;
  }

  /// Whether retrying the operation is likely to help.
  bool isRetryable(Object error) {
    switch (categorize(error)) {
      case ErrorCategory.network:
      case ErrorCategory.timeout:
      case ErrorCategory.server:
      case ErrorCategory.quota:
        return true;
      default:
        return false;
    }
  }

  /// Maps a technical error to a user-friendly message (Phase 17 — Part 3).
  ///
  /// Internal exception messages are never exposed. Returns [fallback] for
  /// unrecognized errors.
  String friendlyMessageFor(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error is TimeoutException) {
      return 'The request took too long. Please check your connection and try again.';
    }
    if (error is http.ClientException) {
      return 'Network error. Please check your internet connection.';
    }
    if (error is FirebaseException) {
      switch (_bareCode(error)) {
        case 'permission-denied':
          return 'You do not have permission to do that.';
        case 'unavailable':
        case 'aborted':
        case 'internal':
          return 'The service is temporarily unavailable. Please try again later.';
        case 'resource-exhausted':
        case 'quota-exceeded':
          return 'The service is busy right now. Please try again later.';
        case 'deadline-exceeded':
          return 'The request took too long. Please try again.';
        case 'cancelled':
          return 'The request was cancelled.';
        case 'not-found':
          return 'The item you are looking for was not found.';
        case 'already-exists':
          return 'That item already exists.';
        case 'network-request-failed':
        case 'channel-error':
          return 'Network error. Please check your internet connection.';
        case 'invalid-argument':
        case 'failed-precondition':
          return 'Something went wrong. Please try again.';
      }
    }
    if (error is PlatformException) {
      final code = _bareCode(error);
      if (code == 'network-request-failed' ||
          code == 'channel-error' ||
          code == 'connection-error') {
        return 'Network error. Please check your internet connection.';
      }
      if (code == 'permission-denied') {
        return 'You do not have permission to do that.';
      }
    }
    if (error is FormatException) return fallback;
    return fallback;
  }

  /// Strips any `firebase_auth/`, `firestore/` style prefix from a code.
  static String _bareCode(Object error) {
    final raw = error is FirebaseException
        ? error.code
        : error is PlatformException
            ? error.code
            : '';
    return raw.contains('/') ? raw.substring(raw.lastIndexOf('/') + 1) : raw;
  }
}

/// Lightweight Cloudinary image-load monitor (Phase 17 — Part 10).
///
/// Tracks failed downloads, slow loads, placeholder frequency and broken
/// URLs. Broken URLs are remembered so widgets can skip re-requesting them
/// instead of repeatedly retrying. All tracking is in-memory and anonymous;
/// only the URL host (never the full URL) is sent to Analytics.
class ImageMonitor {
  ImageMonitor._();

  static final ImageMonitor instance = ImageMonitor._();

  /// Loads slower than this count as a "slow load".
  static const Duration slowThreshold = Duration(milliseconds: 1500);

  final Set<String> _brokenUrls = {};
  final Map<String, Stopwatch> _pending = {};

  int failedLoads = 0;
  int slowLoads = 0;
  int placeholderShown = 0;
  int successfulLoads = 0;
  DateTime? lastSuccessAt;
  DateTime? lastFailureAt;

  /// Whether [url] has already failed once this session — widgets should
  /// render the placeholder without attempting the network again.
  bool isKnownBroken(String url) => _brokenUrls.contains(url);

  int get brokenUrlCount => _brokenUrls.length;

  void reportLoadStart(String url) {
    _pending[url] = Stopwatch()..start();
  }

  void reportLoadEnd(String url, {required bool fromCache}) {
    final sw = _pending.remove(url);
    if (sw == null) return;
    sw.stop();
    successfulLoads++;
    lastSuccessAt = DateTime.now();
    if (!fromCache && sw.elapsed > slowThreshold) {
      slowLoads++;
    }
  }

  /// Drops an in-flight load measurement (e.g. the widget was disposed before
  /// the image resolved) so the pending map never accumulates stale entries.
  void cancelPending(String url) {
    _pending.remove(url);
  }

  /// Records a failed download. Each unique URL is counted once per session
  /// so a broken image cannot inflate the failure rate.
  void reportFailure(String url) {
    _pending.remove(url);
    if (!_brokenUrls.add(url)) return;
    failedLoads++;
    lastFailureAt = DateTime.now();
    AnalyticsService.instance.logEvent(
      AnalyticsEvent.imageLoadFailed,
      params: {'host': _hostOf(url)},
    );
  }

  void reportPlaceholderShown() => placeholderShown++;

  String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } on Exception catch (_) {
      return 'unknown';
    }
  }
}
