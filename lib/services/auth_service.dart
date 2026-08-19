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
import 'input_validator.dart';

/// Service that wraps Firebase Authentication for email/password auth.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Timestamp of the last successful network-backed Auth operation, or null
  /// if none has completed in this session. Used only for health reporting —
  /// never contains user data.
  static DateTime? lastSuccessAt;

  /// Timestamp of the last failed network-backed Auth operation, or null if
  /// none has failed. Used only for health reporting — never user data.
  static DateTime? lastFailureAt;

  static void _record(bool success) {
    final now = DateTime.now();
    if (success) {
      lastSuccessAt = now;
    } else {
      lastFailureAt = now;
    }
  }

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
    // Phase 15 — Part 6: validate the RAW inputs locally before they cross
    // to Firebase Auth. Reject malformed, oversized, or Unicode
    // control-character values here; the sanitized values below are produced
    // ONLY after raw-input validation succeeds.
    if (!InputValidator.isValidEmail(email)) {
      return 'Please enter a valid email address.';
    }
    if (fullName.trim().isEmpty) return 'Please enter your full name.';
    if (InputValidator.containsControlCharacters(fullName)) {
      return 'Name contains invalid characters.';
    }
    if (fullName.trim().length > InputValidator.maxNameLength) {
      return 'Name is too long. Use ${InputValidator.maxNameLength} characters or fewer.';
    }
    if (password.isEmpty) {
      return 'Invalid email or password. Please try again.';
    }
    if (InputValidator.containsControlCharacters(password)) {
      return 'Password contains invalid characters.';
    }
    if (password.length > InputValidator.maxPasswordLength) {
      return 'Password is too long. Use ${InputValidator.maxPasswordLength} characters or fewer.';
    }

    final cleanEmail = InputValidator.sanitizeEmail(email);
    final cleanName = InputValidator.sanitizeName(fullName);

    try {
      final UserCredential credential = await _auth
          .createUserWithEmailAndPassword(
            email: cleanEmail,
            password: password,
          );
      if (credential.user != null) {
        await credential.user!.updateDisplayName(cleanName);
      }
      _record(true);
      return null; // success — Firestore profile is NOT created yet
    } on Exception catch (e, stack) {
      _record(false);
      AppLog.e('[AuthService] register error: type=${e.runtimeType}', e, stack);
      return _extractUserFriendlyError(e);
    }
  }

  // ── Sign-in ─────────────────────────────────────────────────────────────────

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    // Phase 15 — Part 6/14: validate locally BEFORE building the Firebase
    // Auth request. Malformed emails (including control characters), empty
    // passwords, and passwords with control characters are rejected with the
    // same generic credential message — never revealing which field was
    // invalid (anti-enumeration) — and Firebase Auth is not called.
    if (!InputValidator.isValidEmail(email) ||
        password.isEmpty ||
        InputValidator.containsControlCharacters(password)) {
      return 'Invalid email or password. Please try again.';
    }

    try {
      await _auth.signInWithEmailAndPassword(
        email: InputValidator.sanitizeEmail(email),
        password: password,
      );
      _record(true);
      return null; // success
    } on Exception catch (e, stack) {
      _record(false);
      AppLog.e('[AuthService] signIn error: type=${e.runtimeType}', e, stack);
      // Phase 15 — anti-enumeration: sign-in failures must not reveal
      // whether an email exists or whether the password was correct.
      return userFacingSignInError(e);
    }
  }

  // ── Email verification ─────────────────────────────────────────────────────

  /// Sends a Firebase email verification link to the current user.
  Future<String?> sendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No authenticated user found.';
      await user.sendEmailVerification();
      _record(true);
      return null; // success
    } on Exception catch (e) {
      _record(false);
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
      _record(true);
      return null; // success
    } on Exception catch (e) {
      _record(false);
      AppLog.e('[AuthService] reloadUser error: type=${e.runtimeType}');
      return _extractUserFriendlyError(e);
    }
  }

  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Forces a fresh Firebase ID token so the `email_verified` claim (used by
  /// Firestore security rules) reflects the latest server state.
  ///
  /// After the user verifies their email, the cached ID token may still carry
  /// `email_verified: false` until it is refreshed. Rules that gate ordering
  /// on `request.auth.token.email_verified` would reject the order in that
  /// window, so this MUST be called once verification is confirmed.
  ///
  /// Returns `null` on success or a user-facing error message on failure.
  Future<String?> refreshIdToken() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No authenticated user found.';
      await user.getIdToken(true);
      _record(true);
      return null; // success
    } catch (e) {
      _record(false);
      AppLog.e('[AuthService] refreshIdToken error: type=${e.runtimeType}');
      return 'Could not refresh session. Please try again.';
    }
  }

  // ── Password reset ─────────────────────────────────────────────────────────

  /// Sends a password-reset email via Firebase Authentication.
  ///
  /// Always returns the same success message (null) regardless of whether the
  /// email exists, to prevent account enumeration attacks.
  Future<String?> sendPasswordReset({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      _record(true);
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
      _record(true);
      return null; // success — a new verification email is sent automatically
    } on Exception catch (e) {
      _record(false);
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
      _record(true);
      return null; // success
    } on Exception catch (e) {
      _record(false);
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

  /// Maps a sign-in failure to a user-facing string WITHOUT revealing whether
  /// the email exists or the password was correct (Phase 15 — Part 14).
  ///
  /// All authentication-credential errors — unknown email, wrong password,
  /// invalid credential, disabled account — collapse to one generic message.
  /// Explicitly public and static so it can be unit-tested without Firebase.
  static String userFacingSignInError(Object e) {
    final code = _errorCodeOf(e);
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
      case 'user-disabled':
        // Generic message — identical for every outcome.
        return 'Invalid email or password. Please try again.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'invalid-email':
        return 'The email address is not valid.';
      default:
        // Fall back to the shared mapper for anything else.
        return _mapErrorCode(code) ??
            'Authentication failed. Please try again.';
    }
  }

  /// Extracts a bare Firebase error code from [e], stripping any
  /// `firebase_auth/` style prefix and handling pigeon bridge codes.
  static String _errorCodeOf(Object e) {
    String raw = '';
    if (e is FirebaseAuthException) {
      raw = e.code;
    } else if (e is PlatformException) {
      final details = e.details;
      if (details is Map) {
        raw = details['code']?.toString() ?? '';
      }
      if (raw.isEmpty) raw = e.code;
    }
    return raw.contains('/') ? raw.substring(raw.lastIndexOf('/') + 1) : raw;
  }

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
  static String? _mapErrorCode(String rawCode) {
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
      case 'invalid-credential':
      case 'invalid-login-credentials':
        // Single generic message — never discloses email existence or whether
        // the password was correct (Part 14 anti-enumeration).
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
