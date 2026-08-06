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

import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:campusbite/navigation/auth_wrapper.dart';
import 'package:campusbite/navigation/bottom_navigation.dart'; // MainScreen
import 'package:campusbite/screens/help_support.dart';
import 'package:campusbite/screens/terms.dart';
import 'package:campusbite/screens/register_screen.dart';
import 'package:campusbite/screens/login_screen.dart';
import 'package:campusbite/screens/welcome_screen.dart';
import 'package:campusbite/screens/verify_email_screen.dart';
import 'package:campusbite/screens/forgot_password_screen.dart';
import 'package:campusbite/screens/diagnostics_screen.dart';
import 'package:campusbite/screens/not_found_screen.dart';
import 'package:campusbite/services/diagnostics_service.dart';

final AuthNotifier _authNotifier = AuthNotifier();

/// Paths that are allowed for unverified users.
bool _isVerificationPath(String location) {
  return location == '/verify-email' ||
      location == '/' ||
      location == '/login' ||
      location == '/register' ||
      location == '/forgot-password' ||
      location == '/terms';
}

/// Paths that verified users should be redirected from (to go to /main).
bool _isOnboardingPath(String location) {
  return location == '/' ||
      location == '/login' ||
      location == '/register' ||
      location == '/verify-email' ||
      location == '/forgot-password';
}

final GoRouter router = GoRouter(
  initialLocation: '/',
  refreshListenable: _authNotifier,
  errorBuilder: (context, state) => const NotFoundScreen(),
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final loggedIn = user != null;
    final location = state.matchedLocation;

    // Allow unauthenticated users on public paths
    if (!loggedIn) {
      if (location == '/main') return '/';
      return null;
    }

    // ── Verified user on an auth/onboarding path → send to main ────
    // This preserves the original behaviour: logged-in users who land
    // on /, /login, /register, /verify-email, or /forgot-password are
    // redirected to the main app.
    if (user.emailVerified && _isOnboardingPath(location)) return '/main';

    // ── Unverified user on a verification path → allow access ──────
    // These paths (verify-email, forgot-password, login, register,
    // terms, and /) are the only screens an unverified user can see.
    if (!user.emailVerified && _isVerificationPath(location)) return null;

    // ── Unverified user on /main → redirect to verification screen ─
    if (!user.emailVerified && location == '/main') return '/verify-email';

    return null; // no redirect needed
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const WelcomeScreen()),
    GoRoute(path: '/main', builder: (context, state) => const MainScreen()),
    GoRoute(path: '/terms', builder: (context, state) => const TermsScreen()),
    GoRoute(
      path: '/support',
      builder: (context, state) => const SupportScreen(),
      routes: [
        GoRoute(path: 'faq', builder: (context, state) => const FaqScreen()),
        GoRoute(
          path: 'contact',
          builder: (context, state) => const ContactScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/verify-email',
      builder: (context, state) => const VerifyEmailScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/diagnostics',
      redirect: (context, state) async {
        // Hidden screen: debug builds or admin accounts only — same
        // visibility condition as DiagnosticsEntryTile. In release builds a
        // non-admin is redirected away instead of reaching the screen.
        if (kDebugMode) return null;
        try {
          final role = await DiagnosticsService.instance.fetchUserRole();
          if (DiagnosticsEntryTile.shouldShowDiagnostics(
            debugMode: false,
            role: role,
          )) {
            return null;
          }
        } catch (_) {
          // Role lookup failed — fail closed and deny access to the
          // diagnostics route. (fetchUserRole bounds its own Firestore
          // read with a 5s timeout, so no separate timeout is needed here.)
        }
        return '/main';
      },
      builder: (context, state) => const DiagnosticsScreen(),
    ),
  ],
);
