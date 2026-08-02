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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import 'app_log.dart';
import 'input_validator.dart';

/// Service that manages email verification business logic.
///
/// Responsibilities:
/// - Send verification email with rate-limiting cooldown
/// - Reload user and check emailVerified
/// - Create Firestore user profile after successful verification
/// - Handle re-send cooldown (60 seconds)
///
/// Business logic MUST NOT exist inside widgets.
class EmailVerificationService {
  // ── Cooldown state ─────────────────────────────────────────────────────────

  DateTime? _lastResendAt;

  /// Whether the resend cooldown is currently active.
  bool get isResendCooldownActive {
    if (_lastResendAt == null) return false;
    return DateTime.now().difference(_lastResendAt!) <
        const Duration(seconds: 60);
  }

  /// Seconds remaining before the resend cooldown expires.
  int get resendCooldownSeconds {
    if (_lastResendAt == null) return 0;
    final remaining = 60 -
        DateTime.now().difference(_lastResendAt!).inSeconds;
    return remaining.clamp(0, 60);
  }

  // ── Send verification email ────────────────────────────────────────────────

  /// Sends a verification email via [sendFn] and starts the 60-second cooldown.
  ///
  /// [sendFn] is typically `AuthService().sendVerificationEmail`.
  /// Returns `null` on success or an error message on failure.
  /// Does NOT send if the cooldown is still active.
  Future<String?> sendVerificationEmail({
    required Future<String?> Function() sendFn,
  }) async {
    if (isResendCooldownActive) {
      return 'Please wait $resendCooldownSeconds seconds before resending.';
    }
    final error = await sendFn();
    if (error == null) {
      _lastResendAt = DateTime.now();
    }
    return error;
  }

  // ── Check verification status ──────────────────────────────────────────────

  /// Reloads the Firebase user and checks [emailVerified].
  ///
  /// [reloadFn] is typically `AuthService().reloadUser`.
  /// [isVerifiedFn] is typically `() => AuthService().isEmailVerified`.
  /// Returns `true` if the email is now verified.
  Future<bool> checkEmailVerified({
    required Future<String?> Function() reloadFn,
    required bool Function() isVerifiedFn,
  }) async {
    final error = await reloadFn();
    if (error != null) {
      // Log only the type — the raw error string may embed the user's email
      // or other personal data.
      AppLog.e(
        '[EmailVerificationService] reloadUser error: '
        'type=${error.runtimeType}',
      );
      return false;
    }
    return isVerifiedFn();
  }

  // ── Firestore profile creation (after verification) ────────────────────────

  /// Creates the Firestore user profile after email verification.
  ///
  /// Idempotent — safe to call multiple times. If a document already exists
  /// for [user.uid] the method returns `null` (success = already exists).
  Future<String?> createProfileAfterVerification(User user) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        // Phase 15 — input hygiene: strip control characters and enforce
        // length bounds before persisting user-supplied profile fields.
        final fullName = InputValidator.sanitizeName(user.displayName);
        final email = InputValidator.sanitizeEmail(user.email);
        if (fullName.isEmpty || email.isEmpty) {
          return 'Profile name is invalid. Please re-register.';
        }
        await docRef.set(
          UserProfile(
            fullName: fullName,
            email: email,
          ).toFirestoreCreate(),
        );

        // Set welcome screen flag for the newly verified user
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('show_welcome_${user.uid}', true);
      }
      return null; // success
    } catch (e) {
      AppLog.e('[EmailVerificationService] createProfile error: type=${e.runtimeType}');
      return 'Could not create profile. Please try again.';
    }
  }
}
