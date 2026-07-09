import 'dart:async';
import 'package:campusbite/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Notifies go_router whenever Firebase auth state changes, so it can
/// re-evaluate redirects.
class AuthNotifier extends ChangeNotifier {
  AuthNotifier() {
    _subscription = AuthService().authStateChanges.listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<User?> _subscription;

  User? get currentUser => AuthService().authStateChanges.isBroadcast
      ? FirebaseAuth.instance.currentUser
      : null;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
