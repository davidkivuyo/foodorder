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
