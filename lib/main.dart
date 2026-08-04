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

// deepLinkToTabIndex
import 'dart:async';

import 'package:campusbite/navigation/router.dart';
import 'package:campusbite/services/app_log.dart';
import 'package:campusbite/services/connectivity_service.dart';
import 'package:campusbite/services/fcm_service.dart';
import 'package:campusbite/services/notification_service.dart';
import 'package:campusbite/services/sync_queue_service.dart';
import 'package:campusbite/services/update_background.dart';
import 'package:campusbite/services/update_service.dart';
import 'package:campusbite/widgets/offline_banner.dart';
import 'package:campusbite/widgets/update_gate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

/// Optional reCAPTCHA v3 site key for web App Check, injected at build time:
/// `flutter build web --dart-define=RECAPTCHA_SITE_KEY=...`
///
/// Empty (default) is only acceptable for debug builds, which skip web App
/// Check with a warning. Web RELEASE builds without a key fail closed at
/// startup: without attestation the backend would reject every request.
const String kRecaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');

/// Global FCM service instance shared across the app.
///
/// [vapidKey] is required for web push notifications. Obtain from:
/// Firebase Console > Project Settings > Cloud Messaging > Web Push certificates
final FcmService fcmService = FcmService(
  role: NotificationService.roleStudent,
  vapidKey:
      'BH_URF31cImwh5AXlb4gLqWuIgeQ6m8KYovL48DyGYsvBl9rArOr90vbetUVPQDEUD09JBzuMffO6zTlfjN-J2g',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 15 — fail closed: a web RELEASE build without a reCAPTCHA v3 site
  // key cannot attest requests, so App Check-enforced backends would reject
  // every call. Refuse to start instead of running a silently broken app.
  // Only debug builds keep the no-provider path (attestation is not enforced
  // in development) and log a warning.
  if (kIsWeb && !kDebugMode && kRecaptchaSiteKey.isEmpty) {
    AppLog.e(
      '[AppCheck] Web release build missing RECAPTCHA_SITE_KEY — '
      'refusing to start without attestation',
    );
    runApp(const _AppCheckMisconfiguredApp());
    return;
  }

  // Track whether Firebase initialized so every Firebase-dependent setup
  // below is gated behind this readiness flag. If init fails (e.g. no
  // default Firebase app exists), the app degrades safely: FCM, the auth
  // listener and Firestore persistence are skipped instead of throwing.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } on Exception catch (e, stack) {
    AppLog.e('Firebase init error', e, stack);
    // Continue — app degrades gracefully if Firebase is unavailable.
  }

  if (firebaseReady) {
    // ── Phase 15: Firebase App Check ───────────────────────────────────
    // Attest that requests come from the genuine app before any Firestore
    // access. Provider selection:
    //   • Android release — Play Integrity (hardware-backed attestation).
    //   • Android debug   — debug provider (tokens must be registered in
    //                       Firebase Console → App Check → Manage debug
    //                       tokens).
    //   • Web             — reCAPTCHA v3, when a site key is provided via
    //                       --dart-define (see kRecaptchaSiteKey).
    // App Check activation must NEVER crash the app: failures are logged
    // (debug only) and the app continues without attestation tokens, which
    // will surface as permission-denied if the backend enforces App Check.
    try {
      // Null on web without a reCAPTCHA key — allowed for debug builds only
      // (release builds fail closed before Firebase initialization).
      final webProvider = kIsWeb && kRecaptchaSiteKey.isNotEmpty
          ? ReCaptchaV3Provider(kRecaptchaSiteKey)
          : null;
      if (kIsWeb && webProvider == null) {
        AppLog.w(
          '[AppCheck] Web build running without a reCAPTCHA site key — '
          'App Check attestation disabled (debug builds only)',
        );
      }
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerWeb: webProvider,
      );
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
      AppLog.d('Firebase App Check activated');
    } on Exception catch (e, stack) {
      AppLog.e(
        'App Check activation failed — continuing without attestation',
        e,
        stack,
      );
    }
  }

  if (firebaseReady) {
    // ── Phase 13: Firestore offline persistence ─────────────────────────
    // Enable the local cache so menu, food details, categories and reviews
    // render instantly from cache before the network refreshes them.
    // Must be set before any other Firestore operation.
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
      );
      AppLog.d('Firestore offline persistence enabled');
    } on Exception catch (e) {
      AppLog.e('Failed to enable Firestore persistence', e);
    }

    // Register background message handler once at startup (not per-auth).
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundMessageHandler);
  } else {
    AppLog.w('Firebase unavailable — skipping persistence and FCM setup');
  }

  usePathUrlStrategy();
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Campus Bite'],
      '''
The software components of this application incorporate source code include the Apache version 2.0 Open Source License and its following notice.

Copyright 2026 Campus Bite Contributors, Larason

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
  ''',
    );
  });
  // ── Phase 12: Connectivity & Sync Queue bootstrap ───────────────────
  // Eagerly spin up the singleton so the polling timer starts and the
  // SyncQueueService loads any queued operations from SharedPreferences
  // before the first frame is drawn.
  ConnectivityService();
  SyncQueueService();

  runApp(MyApp(firebaseReady: firebaseReady));

  // ── Phase 14: in-app updates ─────────────────────────────────────────
  // Fire-and-forget; every failure path in the update check is swallowed so
  // a network error can never block app startup.
  unawaited(registerPeriodicUpdateCheck());
  unawaited(UpdateService.instance.checkForUpdate());
}

/// Initialize FCM for the current authenticated user.
///
/// Called when auth state changes to logged-in.
/// Deactivates the token when the user logs out.
Future<void> initializeFcmForUser(User? user) async {
  if (user != null) {
    try {
      await fcmService.initialize(userId: user.uid);
    } on Exception catch (e, stack) {
      AppLog.e('[FCM] Initialization error', e, stack);
    }
  } else {
    try {
      await fcmService.onLogout();
    } on Exception catch (e) {
      AppLog.e('[FCM] Logout error', e);
    }
  }
}

// The main widget
class MyApp extends StatefulWidget {
  const MyApp({super.key, this.firebaseReady = true});

  /// Whether Firebase initialized successfully at startup. When false, all
  /// Firebase-dependent wiring (auth listener, FCM) is skipped so the app
  /// degrades safely instead of throwing.
  final bool firebaseReady;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Deduplication: prevent handling the same deep link twice within 5 seconds.
  // This guards against redundant notification-tap processing (e.g., the same
  // FCM notification being delivered via both onMessageOpenedApp and
  // getInitialMessage, or the user tapping the same notification twice).
  String? _lastHandledDeepLink;
  DateTime? _lastHandledAt;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();

    // Initialize FCM when auth state changes — only when Firebase is ready,
    // otherwise FirebaseAuth.instance would throw.
    if (widget.firebaseReady) {
      // Set up deep link navigation callback
      FcmService.onDeepLinkNavigation = _handleDeepLink;

      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        initializeFcmForUser(user);
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _handleDeepLink(String deepLink) {
    // Validate: reject empty deep links
    if (deepLink.isEmpty) {
      AppLog.d('[FCM] Deep link navigation skipped: empty deep link');
      return;
    }

    // Deduplicate: same deep link within 5 seconds is likely a duplicate
    final now = DateTime.now();
    if (deepLink == _lastHandledDeepLink &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(seconds: 5)) {
      AppLog.d('[FCM] Deep link navigation skipped: duplicate $deepLink');
      return;
    }
    _lastHandledDeepLink = deepLink;
    _lastHandledAt = now;

    AppLog.d('[FCM] Deep link navigation: $deepLink');

    // Convert deep link to a main screen tab and navigate via GoRouter.
    // This works whether the user is on the welcome screen or main screen.
    final tabIndex = deepLinkToTabIndex(deepLink);
    if (tabIndex != null) {
      router.go('/main?tab=$tabIndex');
    } else if (deepLink == '/notifications') {
      router.go('/main');
    } else {
      // Unrecognized deep link — fallback to main screen
      AppLog.d(
        '[FCM] Deep link navigation: unrecognized path $deepLink, '
        'falling back to /main',
      );
      router.go('/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      title: 'Food order app',
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.dmSansTextTheme(Theme.of(context).textTheme),
      ),
      // Phase 14: the update gate sits above the navigator so mandatory
      // updates can block the whole app, and optional ones can prompt over
      // any screen.
      // Phase 12: OfflineBanner is added inside UpdateGate so it appears on
      // every screen as a slim status banner above the page content.
      builder: (context, child) => UpdateGate(
        child: Column(
          children: [
            Expanded(child: child ?? const SizedBox()),
            const OfflineBanner(),
          ],
        ),
      ),
    );
  }

  Object? deepLinkToTabIndex(String deepLink) {
    return null;
  }
}

/// Shown when a web release build is missing `RECAPTCHA_SITE_KEY`.
///
/// The app cannot attest requests without it, so it refuses to start
/// (fail closed) rather than run against App Check-enforced backends.
class _AppCheckMisconfiguredApp extends StatelessWidget {
  const _AppCheckMisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.gpp_bad_outlined, size: 56, color: Colors.red),
                SizedBox(height: 16),
                Text(
                  'App cannot start',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'This web build is missing the reCAPTCHA site key required '
                  'for App Check. Please contact support.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
