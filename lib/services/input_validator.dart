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

/// Centralized input validation and sanitization (Phase 15 — Part 6).
///
/// Every user-supplied value that crosses a trust boundary should be passed
/// through these helpers before being persisted or used in comparisons.
///
/// Design notes:
/// - Validation returns a bool; sanitization returns a cleaned string.
/// - Control characters (C0 0x00–0x1F and C1 0x7F–0x9F) are stripped from
///   free-text fields because they can be used for log injection, terminal
///   escape abuse, or malformed payload smuggling.
/// - All length limits mirror the corresponding Firestore security-rule
///   constraints so the client and backend agree on what is acceptable.
class InputValidator {
  InputValidator._();

  /// Maximum length of a display name / full name (matches rules).
  static const int maxNameLength = 100;

  /// Maximum length of an email address (matches rules).
  static const int maxEmailLength = 320;

  /// Maximum length of a phone number (matches rules).
  static const int maxPhoneLength = 20;

  /// Maximum length of a password (Firebase Auth rejects passwords longer
  /// than 1024 characters server-side; reject locally for a clear message).
  static const int maxPasswordLength = 1024;

  /// Simple RFC-5322-ish email check. Deliberately lenient — Firebase Auth
  /// performs the authoritative email validation server-side.
  static bool isValidEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty || email.length > maxEmailLength) return false;
    // The regex character class only excludes whitespace and '@' — control
    // characters (e.g. NUL, C1 controls) would otherwise pass through, so
    // reject them explicitly first (Part 6).
    if (containsControlCharacters(email)) return false;
    final pattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return pattern.hasMatch(email);
  }

  /// Basic phone check: 7–15 numeric digits (ITU E.164 range), with `+`,
  /// `-`, `(`, `)` and single spaces allowed as separators. Rejects control
  /// characters (including newlines/tabs), repeated or unbalanced
  /// separators, and separator-only values. International formats such as
  /// `+255 7XX XXX XXX` and `07XX-XXX-XXX` are accepted; alphabetic
  /// characters are rejected.
  static bool isValidPhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty || phone.length > maxPhoneLength) return false;
    // The separator set below deliberately excludes `\s` so whitespace
    // control characters (newline, tab) cannot pass — reject them outright.
    if (containsControlCharacters(phone)) return false;

    var digitCount = 0;
    var parenBalance = 0;
    String? lastSeparator;
    for (var i = 0; i < phone.length; i++) {
      final char = phone[i];
      final code = char.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) {
        digitCount++;
        lastSeparator = null;
      } else if (char == '+') {
        // '+' is only valid as the leading country-code marker.
        if (i != 0) return false;
      } else if (char == '-') {
        // Reject repeated identical separators (e.g. '--').
        if (lastSeparator == char) return false;
        lastSeparator = char;
      } else if (char == '(') {
        if (lastSeparator == char) return false;
        lastSeparator = char;
        parenBalance++;
      } else if (char == ')') {
        if (lastSeparator == char) return false;
        lastSeparator = char;
        parenBalance--;
        if (parenBalance < 0) return false;
      } else if (char == ' ') {
        // Reject repeated spaces, but allow a single space between groups
        // (e.g. before a parenthesised area code).
        if (lastSeparator == char) return false;
        lastSeparator = char;
      } else {
        // Letters and any other characters are invalid.
        return false;
      }
    }

    // At least 7 digits (and at most 15) ensures separator-only values
    // like '--- ---' are rejected; balanced parentheses reject malformed
    // placements like '0712)345678'.
    return digitCount >= 7 && digitCount <= 15 && parenBalance == 0;
  }

  /// True when [value] contains any Unicode control character.
  static bool containsControlCharacters(String? value) {
    if (value == null || value.isEmpty) return false;
    return value.runes.any((r) => r < 0x20 || (r >= 0x7F && r <= 0x9F));
  }

  /// Strips Unicode control characters from [value].
  static String stripControlCharacters(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) continue;
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  /// Sanitizes a free-text name: trims and collapses internal whitespace.
  ///
  /// Phase 15 — Part 6: validates the RAW input before transforming it.
  /// Names containing Unicode control characters or exceeding
  /// [maxNameLength] are REJECTED (empty string returned) rather than
  /// silently stripped or truncated — a modified value is never persisted.
  ///
  /// Returns an empty string when the input is null, blank, contains control
  /// characters, or exceeds [maxNameLength].
  static String sanitizeName(String? value) {
    if (value == null) return '';
    // Reject control characters on the raw input (log-injection vector).
    if (containsControlCharacters(value)) return '';
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length > maxNameLength) return '';
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Sanitizes an email address: trims surrounding whitespace.
  ///
  /// Phase 15 — Part 6: validates the RAW input before transforming it.
  /// Addresses containing Unicode control characters or exceeding
  /// [maxEmailLength] are REJECTED (empty string returned) rather than
  /// persisted in a modified form.
  ///
  /// Returns an empty string when the input is null, blank, contains control
  /// characters, or exceeds [maxEmailLength].
  static String sanitizeEmail(String? value) {
    if (value == null) return '';
    if (containsControlCharacters(value)) return '';
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length > maxEmailLength) return '';
    return trimmed;
  }
}
