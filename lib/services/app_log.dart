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

import 'package:flutter/foundation.dart';

/// Centralized logging service for CampusBite.
///
/// Replaces scattered `debugPrint` calls with a single gated entry point so
/// that:
/// - Debug/info logs are emitted **only in debug builds** (`kDebugMode`).
/// - Warnings and errors are emitted in all build modes.
/// - Sensitive data (email addresses, auth tokens, UIDs, precise locations,
///   personal information) is never logged.
///
/// The sensitive-data guarantee is enforced at this boundary: every message
/// passes through [sanitize] before emission, and [AppLog.e] only logs the
/// exception [runtimeType] — never the raw exception string.
///
/// Phase 13 (performance & code quality): logging hygiene.
class AppLog {
  AppLog._();

  /// Whether verbose (debug/info) logging is enabled.
  ///
  /// Always `false` in release/profile builds so production output only
  /// contains warnings and errors.
  static bool get _verbose => kDebugMode;

  /// Debug-level log — stripped from release builds.
  static void d(String message) {
    if (_verbose) debugPrint('[CampusBite] ${sanitize(message)}');
  }

  /// Info-level log — stripped from release builds.
  static void i(String message) {
    if (_verbose) debugPrint('[CampusBite] ${sanitize(message)}');
  }

  /// Warning-level log — emitted in all build modes.
  static void w(String message) {
    debugPrint('[CampusBite][warn] ${sanitize(message)}');
  }

  /// Error-level log — emitted in all build modes.
  ///
  /// Only logs the exception [runtimeType] (never the raw exception string,
  /// which can embed sensitive values). Pass an optional [error] to include
  /// its runtime type, and an optional [stack] whose contents are appended
  /// in debug builds only. Stack details are always omitted from non-verbose
  /// (release/profile) logs, and any supplied stack content is passed
  /// through [sanitize] before emission so it cannot bypass redaction.
  static void e(String message, [Object? error, StackTrace? stack]) {
    final safeMessage = sanitize(message);
    if (_verbose) {
      final buffer = StringBuffer(safeMessage);
      if (error != null) buffer.write(' — ${error.runtimeType}');
      if (stack != null) buffer.write('\n${sanitize(stack.toString())}');
      debugPrint('[CampusBite][error] $buffer');
    } else {
      debugPrint('[CampusBite][error] $safeMessage');
    }
  }

  /// Redacts known sensitive patterns from a caller-provided message before
  /// it can be emitted, so the documented guarantee holds even if a call site
  /// accidentally passes raw data (defense-in-depth). Public so call sites and
  /// tests can verify redaction for every supported category.
  ///
  /// Currently strips: email addresses, JWT/FCM tokens, long opaque tokens,
  /// phone numbers, precise coordinate pairs, Firestore `users/<uid>` paths
  /// (UIDs 1–128 chars), and bare Firebase-style UIDs (20–128 chars).
  ///
  /// Limitation: arbitrary prose containing names or street addresses is not
  /// caught by pattern matching — call sites MUST still pass safe, static
  /// summaries and exceptions via the [AppLog.e] error parameter.
  static String sanitize(String message) {
    var m = message;

    // Email addresses → [email]
    m = m.replaceAllMapped(
      RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b'),
      (_) => '[email]',
    );

    // JWT tokens (header.payload.signature) → [token]
    m = m.replaceAllMapped(
      RegExp(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'),
      (_) => '[token]',
    );

    // Firestore user document paths (users/<documentId>) → users/[id].
    // Runs before the long-token rule so a long UID inside a users/ path is
    // still replaced with users/[id] rather than users/[token]. Covers custom
    // UIDs from 1 to 128 characters (Firestore document IDs may contain
    // alphanumerics plus '-' and '_').
    m = m.replaceAllMapped(
      RegExp(r'users/[A-Za-z0-9_-]{1,128}'),
      (_) => 'users/[id]',
    );

    // Long opaque tokens (e.g. FCM registration tokens, ~150+ chars) → [token]
    m = m.replaceAllMapped(
      RegExp(r'[A-Za-z0-9_-]{60,}'),
      (_) => '[token]',
    );

    // Bare Firebase-style UIDs (20–128-char opaque base64url tokens, not
    // inside a users/ path) → [uid]. Catches Firestore auto-IDs, Firebase
    // Auth UIDs and custom UIDs without redacting ordinary short words.
    m = m.replaceAllMapped(
      RegExp(r'(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{20,128}(?![A-Za-z0-9_-])'),
      (_) => '[uid]',
    );

    // Phone numbers (international +254…, parenthesized (415) 555-2671, or
    // local 07xx…, with optional separators) → [phone]
    m = m.replaceAllMapped(
      RegExp(r'(?<!\d)(?:\+?\d{1,3}[\s\-]?)?(?:\(\d{1,4}\)[\s\-]?)?(?:\d{2,4}[\s\-]?\d{3}[\s\-]?\d{3,4}|\d{3}[\s\-]?\d{4})(?!\d)'),
      (_) => '[phone]',
    );

    // Precise coordinates ("39.2083, -6.7924") → [coordinates]
    m = m.replaceAllMapped(
      RegExp(r'-?\d{1,3}\.\d{4,}\s*,\s*-?\d{1,3}\.\d{4,}'),
      (_) => '[coordinates]',
    );

    return m;
  }
}
