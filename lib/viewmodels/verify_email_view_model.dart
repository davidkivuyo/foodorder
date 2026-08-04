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

import 'dart:async';
import 'package:campusbite/services/app_log.dart';
import 'package:campusbite/services/auth_service.dart';
import 'package:campusbite/services/email_verification_service.dart';
import 'package:flutter/foundation.dart';

/// Outcome of a "I've Verified My Email" attempt.
enum VerifyEmailOutcome {
  /// Email is verified, the Firestore profile exists and the ID token was
  /// refreshed — the caller may navigate into the app.
  verified,

  /// The email has not been verified yet.
  notVerified,

  /// Verification could not be finalized (UID changed, profile creation
  /// failed, or the ID token refresh failed). A user-facing message is
  /// available via [message].
  failed,
}

/// ViewModel for [VerifyEmailScreen].
///
/// Owns all verification orchestration so the widget only renders state and
/// triggers actions:
/// - reloading the user and checking `emailVerified`
/// - creating the Firestore profile once verified
/// - forcing a fresh ID token so the `email_verified` claim is present
/// - pinning the authenticated UID across every await and aborting if it
///   changes (sign-out or account switch during the flow)
/// - deciding which user-facing message to surface
///
/// The widget never performs business logic; it observes this ViewModel,
/// calls its actions, and renders the resulting state.
class VerifyEmailViewModel extends ChangeNotifier {
  VerifyEmailViewModel({
    AuthService? authService,
    EmailVerificationService? verificationService,
  })  : _authService = authService ?? AuthService(),
        _verificationService =
            verificationService ?? EmailVerificationService();

  final AuthService _authService;
  final EmailVerificationService _verificationService;

  bool _isLoading = false;
  bool _isResending = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  String? _message;
  bool _disposed = false;

  /// Stops notifying listeners once this ViewModel has been disposed so that
  /// pending async operations can settle without touching a dead notifier.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  bool get isLoading => _isLoading;
  bool get isResending => _isResending;
  int get cooldownSeconds => _cooldownSeconds;

  /// A transient, user-facing message produced by the last action. Consume it
  /// with [consumeMessage] after surfacing it (e.g. via a SnackBar).
  String? get message => _message;

  /// Email of the currently authenticated user, or empty when signed out.
  String get email => _authService.currentUser?.email ?? '';

  /// Whether the resend button should be disabled.
  bool get canResend => _cooldownSeconds <= 0 && !_isResending && !_isLoading;

  /// Runs the full post-verification flow.
  ///
  /// The authenticated UID is pinned before any async work. If the account
  /// whose email was checked is no longer the current account at any point,
  /// the flow aborts with a [VerifyEmailOutcome.failed] outcome.
  Future<VerifyEmailOutcome> verify() async {
    _setLoading(true);

    // Pin the UID BEFORE any async work. The account whose email was checked
    // is the only one allowed to continue — a sign-out or account switch
    // during ANY await must abort the flow.
    final uidAtStart = _authService.currentUser?.uid;

    final isVerified = await _verificationService.checkEmailVerified(
      reloadFn: () => _authService.reloadUser(),
      isVerifiedFn: () => _authService.isEmailVerified,
    );

    // The widget may have been disposed while awaiting; settle silently.
    if (_disposed) return VerifyEmailOutcome.failed;

    if (!isVerified) {
      _setLoading(false);
      _setMessage('Your email has not been verified yet.');
      return VerifyEmailOutcome.notVerified;
    }

    // UID must be unchanged after the verification check.
    if (uidAtStart == null || _authService.currentUser?.uid != uidAtStart) {
      _setLoading(false);
      _setMessage('Could not finalize your session. Please try again.');
      return VerifyEmailOutcome.failed;
    }

    // Create Firestore profile now that email is verified.
    final user = _authService.currentUser;
    if (user != null) {
      final profileError =
          await _verificationService.createProfileAfterVerification(user);
      if (_disposed) return VerifyEmailOutcome.failed;
      if (profileError != null) {
        _setLoading(false);
        _setMessage(profileError);
        return VerifyEmailOutcome.failed;
      }
      // UID must be unchanged after profile creation as well.
      if (_authService.currentUser?.uid != uidAtStart) {
        _setLoading(false);
        _setMessage('Could not finalize your session. Please try again.');
        return VerifyEmailOutcome.failed;
      }
    }

    // Force a fresh ID token so the `email_verified` claim is present on the
    // next Firestore request. Security rules gate order creation on this
    // claim. A failed refresh or a changed/missing user means we must NOT
    // continue: stop with an error instead.
    final tokenError = await _authService.refreshIdToken();
    if (_disposed) return VerifyEmailOutcome.failed;
    if (tokenError != null) {
      AppLog.w('[VerifyEmailViewModel] ID token refresh failed after '
          'verification');
    }

    if (tokenError != null || _authService.currentUser?.uid != uidAtStart) {
      _setLoading(false);
      _setMessage('Could not finalize your session. Please try again.');
      return VerifyEmailOutcome.failed;
    }

    _setLoading(false);
    return VerifyEmailOutcome.verified;
  }

  /// Resends the verification email and starts the 60-second cooldown.
  ///
  /// Returns `true` when the email was sent, `false` otherwise. A user-facing
  /// message is available via [message].
  Future<bool> resend() async {
    if (!canResend) return false;

    _isResending = true;
    _safeNotify();

    final error = await _verificationService.sendVerificationEmail(
      sendFn: () => _authService.sendVerificationEmail(),
    );

    _isResending = false;
    if (_disposed) return false;

    if (error != null) {
      _setMessage(error);
      return false;
    }
    _setMessage('Verification email resent. Check spam if not received.');
    _startCooldown();
    return true;
  }

  /// Deletes the current account so the user can register again with a
  /// different email.
  ///
  /// Returns `null` on success or a user-facing error message on failure.
  Future<String?> changeEmail() async {
    _setLoading(true);
    final error = await _authService.deleteAccount();
    if (!_disposed) {
      _setLoading(false);
    }
    return error;
  }

  /// Signs the current user out.
  Future<void> logout() => _authService.signOut();

  /// Clears the pending [message] after it has been surfaced.
  void consumeMessage() {
    if (_disposed || _message == null) return;
    _message = null;
    _safeNotify();
  }

  void _startCooldown() {
    if (_disposed) return;
    _cooldownTimer?.cancel();
    _cooldownSeconds = 60;
    _safeNotify();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      _cooldownSeconds--;
      if (_cooldownSeconds <= 0) {
        _cooldownSeconds = 0;
        timer.cancel();
      }
      _safeNotify();
    });
  }

  void _setLoading(bool value) {
    if (_disposed || _isLoading == value) return;
    _isLoading = value;
    _safeNotify();
  }

  void _setMessage(String value) {
    if (_disposed) return;
    _message = value;
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _cooldownTimer?.cancel();
    super.dispose();
  }
}
