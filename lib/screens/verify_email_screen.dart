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
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Screen shown after registration (and on login for unverified users).
///
/// The user MUST verify their email before accessing the app.  Firestore
/// profile creation is deferred until verification succeeds.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _authService = AuthService();
  final _verificationService = EmailVerificationService();

  bool _isLoading = false;
  bool _isResending = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // ── I've Verified My Email ────────────────────────────────────────────────

  Future<void> _handleVerify() async {
    setState(() => _isLoading = true);

    // Phase 15: pin the authenticated UID BEFORE any async work. The account
    // whose email was checked is the only one allowed to continue — a
    // sign-out or account switch during ANY await must abort navigation.
    final uidAtStart = _authService.currentUser?.uid;

    final isVerified = await _verificationService.checkEmailVerified(
      reloadFn: () => _authService.reloadUser(),
      isVerifiedFn: () => _authService.isEmailVerified,
    );

    if (!mounted) return;

    if (isVerified) {
      // UID must be unchanged after the verification check.
      if (uidAtStart == null || _authService.currentUser?.uid != uidAtStart) {
        setState(() => _isLoading = false);
        _showSnack('Could not finalize your session. Please try again.');
        return;
      }

      // Create Firestore profile now that email is verified
      final user = _authService.currentUser;
      if (user != null) {
        final profileError =
            await _verificationService.createProfileAfterVerification(user);
        if (profileError != null) {
          setState(() => _isLoading = false);
          _showSnack(profileError);
          return;
        }
        // UID must be unchanged after profile creation as well.
        if (_authService.currentUser?.uid != uidAtStart) {
          setState(() => _isLoading = false);
          _showSnack('Could not finalize your session. Please try again.');
          return;
        }
      }

      // Phase 15: force a fresh ID token so the `email_verified` claim is
      // present on the next Firestore request. Security rules gate order
      // creation on this claim. A failed refresh or a changed/missing user
      // means we must NOT continue: stop with an error instead.
      final tokenError = await _authService.refreshIdToken();
      if (tokenError != null) {
        AppLog.w('[VerifyEmail] ID token refresh failed after verification');
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (tokenError != null || _authService.currentUser?.uid != uidAtStart) {
        _showSnack('Could not finalize your session. Please try again.');
        return;
      }
      context.go('/main');
    } else {
      setState(() => _isLoading = false);
      _showSnack('Your email has not been verified yet.');
    }
  }

  // ── Resend Verification Email ─────────────────────────────────────────────

  Future<void> _handleResend() async {
    if (_cooldownSeconds > 0 || _isResending) return;

    setState(() => _isResending = true);

    final error = await _verificationService.sendVerificationEmail(
      sendFn: () => _authService.sendVerificationEmail(),
    );

    if (!mounted) return;
    setState(() => _isResending = false);

    if (error != null) {
      _showSnack(error);
    } else {
      _showSnack('Verification email resent. Check spam if not received.');
      _startCooldown();
    }
  }

  void _startCooldown() {
    _cooldownSeconds = 60;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownSeconds--;
        if (_cooldownSeconds <= 0) {
          _cooldownSeconds = 0;
          timer.cancel();
        }
      });
    });
  }

  // ── Change Email ──────────────────────────────────────────────────────────

  Future<void> _handleChangeEmail() async {
    // Confirm with the user
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Email?'),
        content: const Text(
          'This will cancel the current registration so you can '
          'register again with a different email address.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Change Email'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isLoading = true);
    final error = await _authService.deleteAccount();
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      _showSnack(error);
    } else {
      // Account deleted — go back to register screen
      context.go('/register');
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> _handleLogout() async {
    await _authService.signOut();
    if (!mounted) return;
    context.go('/');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final email = user?.email ?? '';

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 850;

    Widget body = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),

          // Mail icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mark_email_unread_outlined,
              size: 50,
              color: Colors.green.shade700,
            ),
          ),

          const SizedBox(height: 32),

          const Text(
            'Verify Your Email',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF156D27),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'We sent a verification email to',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            email,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Click the link in the email to verify your account, '
            'then come back and tap the button below.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),

          const SizedBox(height: 20),

          // ── Spam folder notice ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.orange.shade200,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.mail_outline_rounded,
                    size: 20,
                    color: Colors.orange.shade700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade900,
                        height: 1.4,
                      ),
                      children: const [
                        TextSpan(
                          text:
                              'If you don\'t see the email in your ',
                        ),
                        TextSpan(
                          text: 'inbox',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text:
                              ', please check your ',
                        ),
                        TextSpan(
                          text: 'spam',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' or promotions folder and mark it as "Not Spam".',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // I've Verified My Email button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleVerify,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF116522),
                disabledBackgroundColor:
                    const Color(0xFF116522).withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_outlined, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          "I've Verified My Email",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 20),

          // Resend button with cooldown
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: (_cooldownSeconds > 0 || _isResending || _isLoading)
                  ? null
                  : _handleResend,
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: _cooldownSeconds > 0
                      ? Colors.grey.shade300
                      : const Color(0xFF116522),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isResending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _cooldownSeconds > 0
                          ? 'Resend in $_cooldownSeconds s'
                          : 'Resend Verification Email',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: _cooldownSeconds > 0
                            ? Colors.grey
                            : const Color(0xFF116522),
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 32),

          // Change email
          TextButton.icon(
            onPressed: _isLoading ? null : _handleChangeEmail,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text(
              'Change Email',
              style: TextStyle(fontSize: 14),
            ),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade600,
            ),
          ),

          const SizedBox(height: 8),

          // Logout
          TextButton.icon(
            onPressed: _isLoading ? null : _handleLogout,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text(
              'Logout',
              style: TextStyle(fontSize: 14),
            ),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade400,
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );

    if (isDesktop) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: Center(
          child: Container(
            width: 480,
            margin: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: body,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: body),
    );
  }
}
