import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service that wraps Firebase Authentication for email/password auth.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Public helpers ──────────────────────────────────────────────────────────

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // ── Registration ────────────────────────────────────────────────────────────

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
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(credential.user!.uid)
              .set({
            'fullName': fullName.trim(),
            'email': email.trim(),
            'role': 'student',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (dbError) {
          // If Firestore write fails, clean up the authentication user to keep registration atomic
          try {
            await credential.user!.delete();
          } catch (_) {}
          rethrow;
        }
      }
      return null; // success
    } catch (e, stack) {
      debugPrint('[AuthService] register error: $e');
      debugPrint('[AuthService] stack: $stack');
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
    } catch (e, stack) {
      debugPrint('[AuthService] signIn error: $e');
      debugPrint('[AuthService] stack: $stack');
      return _extractUserFriendlyError(e);
    }
  }

  // ── Sign-out ────────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ── Error extraction ────────────────────────────────────────────────────────

  /// Single entry-point that handles every possible exception type thrown by
  /// firebase_auth and returns a clean, user-facing string.
  String _extractUserFriendlyError(Object e) {
    if (e is FirebaseAuthException) {
      debugPrint(
        '[AuthService] FirebaseAuthException — code="${e.code}" message="${e.message}"',
      );

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
      debugPrint(
        '[AuthService] PlatformException — code="${e.code}" message="${e.message}" details=${e.details}',
      );

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

    debugPrint('[AuthService] Unknown exception type: ${e.runtimeType} — $e');
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
