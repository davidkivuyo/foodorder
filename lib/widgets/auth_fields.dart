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

import 'package:flutter/material.dart';

// ── Validators ──────────────────────────────────────────────────────────────

/// Returns an error string if [value] is not a valid UDSM student email,
/// otherwise returns null.
String? validateUniversityEmail(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Email is required.';
  }
  final trimmed = value.trim().toLowerCase();
  // Must match *@student.udsm.ac.tz and be a valid email format.
  final emailRegex = RegExp(r'^[a-zA-Z0-9._%+\-]+@student\.udsm\.ac\.tz$');
  if (!emailRegex.hasMatch(trimmed)) {
    return 'Use your university email';
  }
  return null;
}

/// Returns an error string if [value] does not meet password requirements,
/// otherwise returns null.
///
/// Requirements:
/// - At least 8 characters
/// - Contains at least one special character
String? validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Password is required.';
  }
  if (value.length < 8) {
    return 'Password must be at least 8 characters.';
  }
  final hasSpecialChar = RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\;/]');
  if (!hasSpecialChar.hasMatch(value)) {
    return 'Password must contain at least one special character.';
  }
  return null;
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class FullName extends StatefulWidget {
  final TextEditingController? controller;

  const FullName({super.key, this.controller});

  @override
  State<FullName> createState() => _FullNameState();
}

class _FullNameState extends State<FullName> {
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      keyboardType: TextInputType.name,
      textCapitalization: TextCapitalization.words,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Full name is required.';
        }
        if (value.trim().length < 2) {
          return 'Please enter your full name.';
        }
        return null;
      },
      decoration: InputDecoration(
        hintText: 'Donny',
        hintStyle: const TextStyle(color: Colors.black38),
        prefixIcon: const Icon(
          Icons.person_outline,
          size: 20,
          color: Colors.black,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black26),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black12),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}

class EmailField extends StatefulWidget {
  final TextEditingController? controller;

  const EmailField({super.key, this.controller});

  @override
  State<EmailField> createState() => _EmailFieldState();
}

class _EmailFieldState extends State<EmailField> {
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      validator: validateUniversityEmail,
      decoration: InputDecoration(
        hintText: 'university email',
        hintStyle: const TextStyle(color: Colors.black38),
        prefixIcon: const Icon(
          Icons.alternate_email,
          size: 20,
          color: Colors.black,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black26),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black12),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  final TextEditingController? controller;

  /// When provided, validates that this field's value matches [matchController].
  final TextEditingController? matchController;

  /// Label for the match error (e.g. "Passwords do not match").
  final bool isConfirmField;

  const PasswordField({
    super.key,
    this.controller,
    this.matchController,
    this.isConfirmField = false,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscurePassword,
      validator: (value) {
        if (widget.isConfirmField) {
          if (value == null || value.isEmpty) {
            return 'Please confirm your password.';
          }
          if (widget.matchController != null &&
              value != widget.matchController!.text) {
            return 'Passwords do not match.';
          }
          return null;
        }
        return validatePassword(value);
      },
      decoration: InputDecoration(
        hintText: '••••••••',
        hintStyle: const TextStyle(color: Colors.black38),
        prefixIcon: const Icon(
          Icons.lock_outline,
          size: 20,
          color: Colors.black,
        ),
        suffixIcon: GestureDetector(
          onTap: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
          child: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 20,
            color: Colors.black,
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black26),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black12),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}
