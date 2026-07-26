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

import 'package:campusbite/services/auth_service.dart';
import 'package:campusbite/widgets/auth_fields.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Screen that allows users to request a password reset email.
///
/// Security note: The success message is always the same regardless of whether
/// the email exists, to prevent account enumeration attacks.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleReset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Always return the same success message (anti-enumeration).
    // The Firebase error is swallowed internally by AuthService.
    await _authService.sendPasswordReset(
      email: _emailController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    // Always show the same message regardless of error or success.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'If an account exists, a reset email has been sent. '
          'Check your spam folder if you don\'t see it.',
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
      ),
    );

    // Navigate back to login after a brief delay
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 850;

    Widget body = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),

          // Lock icon
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock_reset_outlined,
              size: 44,
              color: Colors.orange.shade700,
            ),
          ),

          const SizedBox(height: 28),

          const Text(
            'Forgot Password?',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF156D27),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'Enter your email address and we will send you a '
            'link to reset your password.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade600,
            ),
          ),

          const SizedBox(height: 36),

          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Student Email',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                EmailField(controller: _emailController),
                const SizedBox(height: 28),

                // Send Reset Email button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleReset,
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
                        : const Text(
                            'Send Reset Email',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Spam folder notice ────────────────────────────────────────
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
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Back to Login
          TextButton.icon(
            onPressed: _isLoading
                ? null
                : () => context.go('/login'),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text(
              'Back to Login',
              style: TextStyle(fontSize: 15),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF116522),
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
            width: 450,
            margin: const EdgeInsets.symmetric(vertical: 40),
            padding: const EdgeInsets.all(32),
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
            child: body,
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
