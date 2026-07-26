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
import 'package:campusbite/navigation/auth_wrapper.dart';
import 'package:campusbite/navigation/bottom_navigation.dart'; // MainScreen
import 'package:campusbite/screens/help_support.dart';
import 'package:campusbite/screens/terms.dart';
import 'package:campusbite/screens/register_screen.dart';
import 'package:campusbite/screens/login_screen.dart';
import 'package:campusbite/screens/welcome_screen.dart';
import 'package:campusbite/screens/verify_email_screen.dart';
import 'package:campusbite/screens/forgot_password_screen.dart';

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

final GoRouter router = GoRouter(
  initialLocation: '/',
  refreshListenable: _authNotifier,
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final loggedIn = user != null;
    final location = state.matchedLocation;

    // Allow unauthenticated users on public paths
    if (!loggedIn) {
      if (location == '/main') return '/';
      return null;
    }

    // ── Logged in — reload user to get fresh emailVerified ─────────
    // We call reload() here as a best effort; the real check happens
    // after login/registration where reload is called explicitly.
    // This redirect is a safety net.

    // Allow access to verification paths regardless of emailVerified
    if (_isVerificationPath(location)) return null;

    // If the user is on the main app but NOT verified, redirect them
    // Reload and check emailVerified
    // Note: reload() is async but redirect is sync. We check
    // the cached value and rely on the explicit checks in
    // login_screen and register_screen to redirect to /verify-email.
    // This guard prevents direct URL access to /main for unverified users.
    if (!user.emailVerified && location == '/main') {
      return '/verify-email';
    }

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
  ],
);
