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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../data/food_data.dart';
import 'app_log.dart';

/// Service that wraps Firebase Authentication for email/password auth.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Public helpers ──────────────────────────────────────────────────────────

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // ── Registration ────────────────────────────────────────────────────────────

  /// Creates a Firebase Auth account.  Does NOT write to Firestore — that
  /// happens only after the user verifies their email (see
  /// [EmailVerificationService]).
  Future<String?> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final UserCredential credential = await _auth
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
      if (credential.user != null) {
        await credential.user!.updateDisplayName(fullName.trim());
      }
      return null; // success — Firestore profile is NOT created yet
    } on Exception catch (e, stack) {
      AppLog.e('[AuthService] register error: type=${e.runtimeType}', e, stack);
      return _extractUserFriendlyError(e);
    }
  }

  // ── Sign-in ─────────────────────────────────────────────────────────────────

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return null; // success
    } on Exception catch (e, stack) {
      AppLog.e('[AuthService] signIn error: type=${e.runtimeType}', e, stack);
      return _extractUserFriendlyError(e);
    }
  }

  // ── Email verification ─────────────────────────────────────────────────────

  /// Sends a Firebase email verification link to the current user.
  Future<String?> sendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No authenticated user found.';
      await user.sendEmailVerification();
      return null; // success
    } on Exception catch (e) {
      AppLog.e('[AuthService] sendVerificationEmail error: type=${e.runtimeType}');
      return _extractUserFriendlyError(e);
    }
  }

  /// Reloads the current Firebase user so [isEmailVerified] reflects the
  /// latest state from the server.
  Future<String?> reloadUser() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No authenticated user found.';
      await user.reload();
      return null; // success
    } on Exception catch (e) {
      AppLog.e('[AuthService] reloadUser error: type=${e.runtimeType}');
      return _extractUserFriendlyError(e);
    }
  }

  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  // ── Password reset ─────────────────────────────────────────────────────────

  /// Sends a password-reset email via Firebase Authentication.
  ///
  /// Always returns the same success message (null) regardless of whether the
  /// email exists, to prevent account enumeration attacks.
  Future<String?> sendPasswordReset({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null; // success — same response for all outcomes
    } on Exception catch (e) {
      // Log the actual Firebase error code (safe for internal debugging).
      // The user-facing response stays the same for anti-enumeration.
      if (e is FirebaseAuthException) {
        AppLog.e('[AuthService] sendPasswordReset error: code="${e.code}"');
      } else {
        AppLog.e('[AuthService] sendPasswordReset error: type=${e.runtimeType}');
      }
      // Always return null so attackers cannot distinguish "user-not-found"
      // from "invalid-email" or other failures.
      return null;
    }
  }

  // ── Account management ─────────────────────────────────────────────────────

  /// Updates the email address of an unverified account.
  Future<String?> changeEmail({required String newEmail}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No authenticated user found.';
      await user.verifyBeforeUpdateEmail(newEmail.trim());
      return null; // success — a new verification email is sent automatically
    } on Exception catch (e) {
      AppLog.e('[AuthService] changeEmail error: type=${e.runtimeType}');
      return _extractUserFriendlyError(e);
    }
  }

  /// Deletes the current Firebase Auth account.
  /// Used when a user cancels registration and the profile was not yet created.
  Future<String?> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No authenticated user found.';
      await user.delete();
      return null; // success
    } on Exception catch (e) {
      AppLog.e('[AuthService] deleteAccount error: type=${e.runtimeType}');
      return _extractUserFriendlyError(e);
    }
  }

  // ── Sign-out ────────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _auth.signOut();
    // Reset the shared Firestore menu/section streams: after sign-out their
    // listeners would fail with permission-denied and never recover.
    FoodData.resetStreams();
  }

  // ── Error extraction ────────────────────────────────────────────────────────

  /// Single entry-point that handles every possible exception type thrown by
  /// firebase_auth and returns a clean, user-facing string.
  String _extractUserFriendlyError(Object e) {
    if (e is FirebaseAuthException) {
      AppLog.e('[AuthService] FirebaseAuthException — code="${e.code}"');

      // Try mapping by code first.
      final mapped = _mapErrorCode(e.code);
      if (mapped != null) return mapped;

      // The code or message may be an internal pigeon bridge path — hide it.
      if (_isInternalString(e.code) || _isInternalString(e.message ?? '')) {
        return 'Authentication failed. Please check your credentials and try again.';
      }

      final msg = e.message ?? '';
      return msg.isNotEmpty ? msg : 'Authentication failed. Please try again.';
    }

    if (e is PlatformException) {
      // Log only the stable code — the raw message may embed the user's
      // email, token, or other sensitive values.
      AppLog.e('[AuthService] PlatformException — code="${e.code}"');

      // Details map may carry the real Firebase code.
      if (e.details is Map) {
        final code = (e.details as Map)['code']?.toString() ?? '';
        final mapped = _mapErrorCode(code);
        if (mapped != null) return mapped;
      }

      // Hide internal pigeon paths surfaced via code or message.
      if (_isInternalString(e.code) || _isInternalString(e.message ?? '')) {
        return 'Authentication failed. Please check your credentials and try again.';
      }

      final msg = e.message ?? '';
      return msg.isNotEmpty ? msg : 'Authentication failed. Please try again.';
    }

    AppLog.e('[AuthService] Unknown exception type: ${e.runtimeType}');
    return 'An unexpected error occurred. Please try again.';
  }

  /// Returns true if [s] looks like an internal pigeon bridge identifier that
  /// should never be shown to users.
  bool _isInternalString(String s) {
    return s.contains('dev.flutter') ||
        s.contains('pigeon') ||
        s.contains('FirebaseAuthHostApi');
  }

  /// Maps a Firebase Auth error code to a user-facing string.
  /// Handles both bare codes ("email-already-in-use") and prefixed codes
  /// ("firebase_auth/email-already-in-use").
  String? _mapErrorCode(String rawCode) {
    // Strip any prefix like "firebase_auth/" so we compare bare codes.
    final code = rawCode.contains('/')
        ? rawCode.substring(rawCode.lastIndexOf('/') + 1)
        : rawCode;

    switch (code) {
      case 'email-already-in-use':
        return 'An account with this email already exists. Please login.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled. Contact support.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters with a special character.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'user-not-found':
        return 'No account found for this email. Please register first.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Invalid email or password. Please try again.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'channel-error':
        return 'A connection error occurred. Please try again.';
      default:
        return null;
    }
  }
}
