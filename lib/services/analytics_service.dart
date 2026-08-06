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

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'logger_service.dart';

/// Application analytics events (Phase 17 — Part 5).
///
/// Events are anonymous: event names and parameters are allow-listed, and
/// string parameter values pass through [LoggerService.sanitize] before
/// sending. Emails, UIDs, search text, review text, locations, notification
/// content and passwords are never collected.
enum AnalyticsEvent {
  userRegistered('user_registered'),
  userLoggedIn('user_logged_in'),
  userLoggedOut('user_logged_out'),
  foodViewed('food_viewed'),
  foodSearched('food_searched'),
  foodFavourited('food_favourited'),
  foodUnfavourited('food_unfavourited'),
  addedToCart('added_to_cart'),
  removedFromCart('removed_from_cart'),
  orderPlaced('order_placed'),
  orderCancelled('order_cancelled'),
  orderCollected('order_collected'),
  reviewSubmitted('review_submitted'),
  notificationOpened('notification_opened'),
  updateAvailable('update_available'),
  updateStarted('update_started'),
  updateDownloadFailed('update_download_failed'),
  updateVerificationFailed('update_verification_failed'),
  updateInstallFailed('update_install_failed'),
  updateInstalled('update_installed'),
  imageLoadFailed('image_load_failed'),
  firestoreError('firestore_error'),
  errorOccurred('error_occurred');

  const AnalyticsEvent(this.name);

  /// Firebase Analytics event name (lowercase, underscore-separated).
  final String name;
}

/// Allow-listed analytics parameter keys. Anything else is dropped before
/// the event is sent, so call sites cannot accidentally introduce PII.
const Set<String> kAnalyticsAllowedParams = {
  'category',
  'screen',
  'item_count',
  'value',
  'host',
  'error_type',
  'result',
  'stage',
};

/// Fixed allow-list of screen names that may be sent to Analytics. Dynamic
/// routes, route parameters, and any other caller input are rejected before
/// reaching the backend, so no URL fragments or identifiers can leak.
const Set<String> kAnalyticsScreenNames = {
  'home',
  'categories',
  'category',
  'search',
  'orders',
  'account',
  'favorites',
  'cart',
  'checkout',
  'food_details',
  'notifications',
  'reviews',
  'login',
  'register',
  'welcome',
  'forgot_password',
  'verify_email',
  'diagnostics',
  'help_support',
  'terms',
};

/// Analytics backend — swapped for a recording fake in tests.
@visibleForTesting
abstract class AnalyticsBackend {
  Future<void> setCollectionEnabled(bool enabled);

  Future<void> logEvent(String name, Map<String, Object> parameters);

  Future<void> logScreenView(String screenName);
}

/// Production backend backed by the Firebase Analytics SDK.
class _FirebaseAnalyticsBackend implements AnalyticsBackend {
  const _FirebaseAnalyticsBackend();

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);
  }

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) {
    // Return (do not discard) the SDK future so callers can consume its
    // rejections instead of leaving an unhandled async error.
    return FirebaseAnalytics.instance.logEvent(
      name: name,
      parameters: parameters,
    );
  }

  @override
  Future<void> logScreenView(String screenName) {
    return FirebaseAnalytics.instance.logScreenView(screenName: screenName);
  }
}

/// Firebase Analytics integration (Phase 17 — Part 5).
///
/// All calls are fire-and-forget and internally guarded: when Analytics is
/// unavailable (not initialized, platform error) events are silently dropped
/// so monitoring never interrupts application usage.
class AnalyticsService {
  AnalyticsService._([AnalyticsBackend? backend])
      : _backend = backend ?? const _FirebaseAnalyticsBackend();

  static final AnalyticsService instance = AnalyticsService._();

  AnalyticsBackend _backend;
  bool _available = false;
  bool _initialized = false;
  Timer? _retryTimer;
  int _retryAttempts = 0;

  /// Upper bound on re-initialization attempts so recovery never becomes
  /// continuous polling. Once exceeded, analytics stays unavailable until the
  /// next app launch.
  static const int _maxRetryAttempts = 3;
  static const Duration _retryDelay = Duration(seconds: 30);

  bool get isAvailable => _available;

  /// Test seam: installs a recording fake backend (or restores the Firebase
  /// backend when `null`). Resets availability so the next [initialize]
  /// uses the new backend.
  @visibleForTesting
  void debugSetBackend(AnalyticsBackend? backend) {
    _backend = backend ?? const _FirebaseAnalyticsBackend();
    _available = false;
    _initialized = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempts = 0;
  }

  Future<void> initialize() async {
    _initialized = true;
    try {
      await _backend.setCollectionEnabled(true);
      _available = true;
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryAttempts = 0;
    } catch (e) {
      // Swallow every failure (including non-Exception errors when Firebase
      // is uninitialized) — analytics must never break the app.
      LoggerService.instance.debug('Analytics unavailable (${e.runtimeType})');
      _scheduleRetry();
    }
  }

  /// Schedules a single bounded re-initialization attempt. Guarded so at most
  /// one timer is ever pending and the total number of attempts is capped —
  /// no continuous polling or unbounded scheduling. Called from [initialize]
  /// on failure and again when a later analytics call finds the service
  /// unavailable.
  void _scheduleRetry() {
    if (_available || _retryTimer != null) return;
    if (_retryAttempts >= _maxRetryAttempts) return;
    _retryAttempts++;
    _retryTimer = Timer(_retryDelay, () {
      _retryTimer = null;
      initialize();
    });
  }

  /// Logs an allow-listed event with allow-listed, sanitized parameters.
  void logEvent(
    AnalyticsEvent event, {
    Map<String, Object> params = const {},
  }) {
    if (!_available) {
      // A later analytics call triggers a bounded re-initialization attempt,
      // but only once initialize() has actually run — otherwise the retry
      // timer would be scheduled spuriously on every call in environments
      // where analytics was never bootstrapped (e.g. widget tests), leaving
      // a pending timer that fails the fake-async invariants.
      if (_initialized) _scheduleRetry();
      return;
    }
    try {
      // Fire-and-forget: consume the future so an asynchronous platform
      // failure is a swallowed no-op, never an unhandled zone error. The
      // try/catch still covers synchronous throws.
      unawaited(
        _backend.logEvent(event.name, _sanitizeParams(params)).catchError((_) {
          // A backend logging failure means analytics is no longer usable;
          // mark it unavailable and schedule a bounded recovery attempt.
          _available = false;
          _scheduleRetry();
        }),
      );
    } catch (_) {
      // Synchronous throw — same behavior as the async path.
      _available = false;
      _scheduleRetry();
    }
  }

  /// Logs a screen view. Only names from [kAnalyticsScreenNames] are accepted;
  /// all other input is dropped so dynamic routes, route parameters and any
  /// other caller-supplied identifiers can never reach Analytics.
  void logScreenView(String screenName) {
    if (!_available) {
      // Same gating as logEvent — only re-init if bootstrapping was attempted.
      if (_initialized) _scheduleRetry();
      return;
    }
    if (!kAnalyticsScreenNames.contains(screenName)) return;
    try {
      unawaited(
        _backend.logScreenView(screenName).catchError((_) {
          // Backend logging failure — mark unavailable and schedule recovery.
          _available = false;
          _scheduleRetry();
        }),
      );
    } catch (_) {
      // Synchronous throw — same behavior as the async path.
      _available = false;
      _scheduleRetry();
    }
  }

  Map<String, Object> _sanitizeParams(Map<String, Object> params) {
    final out = <String, Object>{};
    params.forEach((key, value) {
      if (!kAnalyticsAllowedParams.contains(key)) return;
      // Firebase Analytics supports only String and num (int/double)
      // parameter values — maps, lists, custom objects, booleans and other
      // types are dropped rather than forwarded to the SDK.
      if (value is String) {
        out[key] = LoggerService.sanitize(value);
      } else if (value is num) {
        out[key] = value;
      }
    });
    return out;
  }
}
