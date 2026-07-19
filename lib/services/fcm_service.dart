// Copyright 2026 davidkivuyo, johnsonmushi, edwinkessy276-art, jugraki-art.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'device_token_repository.dart';

/// Service that manages FCM token lifecycle and handles incoming push
/// notifications on the client side.
///
/// Responsibilities:
/// - Register the device token on app startup and auth state changes
/// - Listen for token refresh and update Firestore
/// - Handle foreground messages (in-app awareness)
/// - Handle background messages
/// - Handle notification taps (deep link navigation)
///
/// Phase 8: Business logic stays in NotificationService.
/// FCM service only handles token and push delivery — no business logic.
class FcmService {
  final DeviceTokenRepository _tokenRepository;
  final String _role;

  /// Web VAPID key for Firebase Cloud Messaging.
  ///
  /// Required for web push notifications. Obtain from:
  /// Firebase Console > Project Settings > Cloud Messaging > Web Push certificates
  ///
  /// Set to your VAPID public key string (e.g. "BAlk...").
  /// When null or empty, web push will attempt auto-configuration
  /// via the project's messagingSenderId.
  final String? _vapidKey;

  /// Callback invoked when a notification deepLink should be navigated.
  /// Set this from the app's navigation layer.
  static void Function(String deepLink)? onDeepLinkNavigation;

  /// Callback invoked when a foreground push notification arrives.
  /// Receives the notification title and body so the app can show an
  /// in-app banner (e.g. SnackBar). Set this from the app's UI layer.
  static void Function({required String title, required String body})?
      onForegroundNotification;

  // Track all stream subscriptions so they can be cancelled cleanly.
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;

  // The currently authenticated user ID, stored during initialize() so that
  // onLogout() can target the correct device document for deactivation.
  String? _currentUserId;

  FcmService({
    required this._role,
    DeviceTokenRepository? tokenRepository,
    String? vapidKey,
  })  : _vapidKey = vapidKey,
        _tokenRepository = tokenRepository ?? DeviceTokenRepository();

  // ── Initialization ─────────────────────────────────────────────────────────

  /// Initialize the FCM service.
  ///
  /// Must be called after [Firebase.initializeApp()] and when a user is
  /// authenticated.
  ///
  /// This method is idempotent: calling it multiple times safely cancels any
  /// existing subscriptions before registering new ones.
  ///
  /// Returns `true` if the token was successfully registered.
  Future<bool> initialize({required String userId}) async {
    if (userId.isEmpty) return false;

    // Idempotent: cancel any previous subscriptions before reinitializing.
    _cancelSubscriptions();

    try {
      final messaging = FirebaseMessaging.instance;

      // Request notification permissions (Android & iOS)
      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (!_permissionGranted(permission)) {
        debugPrint('[FcmService] Notification permission not granted');
        return false;
      }

      // Get the current FCM token
      // On web, the VAPID key is required for the browser's Push API.
      // On Android/iOS, the vapidKey parameter is ignored by the SDK.
      final token = await messaging.getToken(
        vapidKey: _vapidKey?.isNotEmpty == true ? _vapidKey : null,
      );

      // 🔍 DEBUG: Log the raw token and userId so you can see them in adb logcat.
      // Grep with: adb logcat | grep -i "FCM_TOKEN"
      debugPrint(
        '[FcmService] FCM_TOKEN >>> ${token ?? "null"}  (userId=$userId)',
      );

      if (token == null || token.isEmpty) {
        debugPrint('[FcmService] No FCM token available');
        return false;
      }

      // Register the token in Firestore
      final registered = await _tokenRepository.registerToken(
        userId: userId,
        role: _role,
        token: token,
      );

      if (!registered) {
        debugPrint('[FcmService] Token registration failed');
        return false;
      }

      // Remember the current user for logout deactivation
      _currentUserId = userId;

      // Listen for token refresh — store subscription for later cleanup
      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) {
        _handleTokenRefresh(userId: userId, newToken: newToken);
      });

      // Set up message handlers — store subscriptions for later cleanup
      _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleNotificationTap,
      );

      // Handle notification that opened the app from terminated state (one-shot)
      messaging.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          _handleNotificationTap(message);
        }
      });

      debugPrint('[FcmService] Initialized successfully for user $userId');
      return true;
    } catch (e, stack) {
      debugPrint('[FcmService] Initialization error: $e\n$stack');
      return false;
    }
  }

  /// Cancel all active subscriptions — safe to call multiple times.
  void _cancelSubscriptions() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _onMessageSub?.cancel();
    _onMessageSub = null;
    _onMessageOpenedAppSub?.cancel();
    _onMessageOpenedAppSub = null;
  }

  /// Called when the user logs out — deactivate the token and clean up
  /// all subscriptions so no handlers remain active for the previous user.
  ///
  /// Clears [_currentUserId] only after the device-token deactivation
  /// succeeds, so a transient failure does not lose the user ID needed
  /// for a subsequent retry.
  Future<void> onLogout() async {
    // Cancel all subscriptions first — no handlers can fire for the old user.
    _cancelSubscriptions();

    final userId = _currentUserId;
    if (userId == null) return;

    try {
      final deactivated = await _tokenRepository.deactivateToken(
        userId: userId,
      );

      if (deactivated) {
        // Only clear the userId once the token has been successfully
        // deactivated in Firestore.
        _currentUserId = null;
        debugPrint('[FcmService] Token deactivated for user $userId');
      } else {
        debugPrint(
          '[FcmService] Token deactivation returned false for user $userId '
          '- keeping userId for potential retry',
        );
      }
    } catch (e) {
      debugPrint(
        '[FcmService] Token deactivation error for user $userId: $e '
        '- keeping userId for potential retry',
      );
    }
  }

  // ── Token Refresh ─────────────────────────────────────────────────────────

  Future<void> _handleTokenRefresh({
    required String userId,
    required String newToken,
  }) async {
    try {
      final registered = await _tokenRepository.registerToken(
        userId: userId,
        role: _role,
        token: newToken,
      );

      if (registered) {
        debugPrint('[FcmService] Token refreshed and registered');
      } else {
        debugPrint('[FcmService] Token refresh registration failed');
      }
    } catch (e) {
      debugPrint('[FcmService] Token refresh registration error: $e');
    }
  }

  /// Handle a foreground message — show in-app banner notification.
  ///
  /// The backend writes the notification to Firestore FIRST, then sends
  /// the push via the onNewNotification trigger. The notification already
  /// exists in Firestore by the time the app receives it, so no additional
  /// Firestore write is needed here.
  void _handleForegroundMessage(RemoteMessage message) {
    try {
      final notification = message.notification;

      if (notification == null) {
        debugPrint('[FcmService] Foreground message without notification payload');
        return;
      }

      debugPrint(
        '[FcmService] Foreground notification: ${notification.title}',
      );

      // Show in-app banner via the app's UI callback
      onForegroundNotification?.call(
        title: notification.title ?? '',
        body: notification.body ?? '',
      );
    } catch (e) {
      debugPrint('[FcmService] Foreground message handling error: $e');
    }
  }

  /// Handle a notification tap — navigate via deep link.
  void _handleNotificationTap(RemoteMessage message) {
    try {
      final data = message.data;
      final deepLink = data['deepLink'] as String?;

      if (deepLink != null && deepLink.isNotEmpty) {
        debugPrint('[FcmService] Notification tap — navigating to: $deepLink');
        onDeepLinkNavigation?.call(deepLink);
      }
    } catch (e) {
      debugPrint('[FcmService] Notification tap handling error: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool _permissionGranted(NotificationSettings settings) {
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }
}

/// Background message handler — must be a top-level public function.
///
/// This is called by Firebase when a push notification arrives while the
/// app is in the background.
@pragma('vm:entry-point')
Future<void> fcmBackgroundMessageHandler(RemoteMessage message) async {
  debugPrint(
    '[FcmService] Background message received: ${message.messageId}',
  );

  // The backend has already written the notification to Firestore before
  // sending the push, so there's no additional work needed here.
  // The notification will be available in Firestore when the user opens the app.
  //
  // If the app was terminated and the user taps the notification,
  // getInitialMessage() will handle the deepLink navigation.
}
