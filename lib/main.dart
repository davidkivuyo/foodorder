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

import 'package:campusbite/navigation/bottom_navigation.dart'; // deepLinkToTabIndex
import 'package:campusbite/navigation/router.dart';
import 'package:campusbite/services/fcm_service.dart';
import 'package:campusbite/services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

/// Global FCM service instance shared across the app.
final FcmService fcmService = FcmService(
  role: NotificationService.roleStudent,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, stack) {
    debugPrint('Firebase init error: $e\n$stack');
    // Continue — app degrades gracefully if Firebase is unavailable.
  }

  // Register background message handler once at startup (not per-auth).
  FirebaseMessaging.onBackgroundMessage(fcmBackgroundMessageHandler);

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
  runApp(const MyApp());
}

/// Initialize FCM for the current authenticated user.
///
/// Called when auth state changes to logged-in.
/// Deactivates the token when the user logs out.
Future<void> initializeFcmForUser(User? user) async {
  if (user != null) {
    try {
      await fcmService.initialize(userId: user.uid);
    } catch (e, stack) {
      debugPrint('[FCM] Initialization error: $e\n$stack');
    }
  } else {
    try {
      await fcmService.onLogout();
    } catch (e) {
      debugPrint('[FCM] Logout error: $e');
    }
  }
}

// The main widget
class MyApp extends StatefulWidget {
  const MyApp({super.key});

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

  @override
  void initState() {
    super.initState();

    // Set up deep link navigation callback
    FcmService.onDeepLinkNavigation = _handleDeepLink;

    // Initialize FCM when auth state changes
    FirebaseAuth.instance.authStateChanges().listen((user) {
      initializeFcmForUser(user);
    });
  }

  void _handleDeepLink(String deepLink) {
    // Validate: reject empty deep links
    if (deepLink.isEmpty) {
      debugPrint('[FCM] Deep link navigation skipped: empty deep link');
      return;
    }

    // Deduplicate: same deep link within 5 seconds is likely a duplicate
    final now = DateTime.now();
    if (deepLink == _lastHandledDeepLink &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(seconds: 5)) {
      debugPrint('[FCM] Deep link navigation skipped: duplicate $deepLink');
      return;
    }
    _lastHandledDeepLink = deepLink;
    _lastHandledAt = now;

    debugPrint('[FCM] Deep link navigation: $deepLink');

    // Convert deep link to a main screen tab and navigate via GoRouter.
    // This works whether the user is on the welcome screen or main screen.
    final tabIndex = deepLinkToTabIndex(deepLink);
    if (tabIndex != null) {
      router.go('/main?tab=$tabIndex');
    } else if (deepLink == '/notifications') {
      router.go('/main');
    } else {
      // Unrecognized deep link — fallback to main screen
      debugPrint(
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
    );
  }
}
