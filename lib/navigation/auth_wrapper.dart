import 'package:campusbite/screens/login_screen.dart';
import 'package:campusbite/navigation/bottom_navigation.dart';
import 'package:campusbite/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Listens to Firebase auth-state changes and routes the user to either the
/// authenticated [MainScreen] or the unauthenticated [LoginScreen].
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        // While Firebase resolves the persisted session, show a loading screen.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF116522),
              ),
            ),
          );
        }

        // Logged-in → main app experience
        if (snapshot.hasData && snapshot.data != null) {
          return const MainScreen();
        }

        // Logged-out → login screen (which navigates to register when needed)
        return const LoginScreen();
      },
    );
  }
}
