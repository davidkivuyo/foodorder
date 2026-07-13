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
import 'package:campusbite/main.dart'; // WelcomeScreen

final AuthNotifier _authNotifier = AuthNotifier();

final GoRouter router = GoRouter(
  initialLocation: '/',
  refreshListenable: _authNotifier,
  redirect: (context, state) {
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    final loggingInFlow =
        state.matchedLocation == '/' ||
        state.matchedLocation == '/login' ||
        state.matchedLocation == '/register';

    // Logged in but sitting on welcome/login/register → send to main
    if (loggedIn && loggingInFlow) return '/main';

    // Logged out but trying to reach the app → send to welcome
    if (!loggedIn && state.matchedLocation == '/main') return '/';

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
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
  ],
);
