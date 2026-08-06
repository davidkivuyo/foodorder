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

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Log levels supported by [LoggerService] (Phase 17 — Part 4).
enum LogLevel { debug, info, warning, error, critical }

/// Structured logging service (Phase 17 — Part 4).
///
/// Single gated entry point for all application logging:
/// - debug/info are emitted only in debug builds;
/// - warning/error/critical are emitted in all build modes;
/// - every message passes through [sanitize] so sensitive data (emails,
///   UIDs, tokens, phones, coordinates) can never reach the console.
///
/// [AppLog] remains as a non-breaking facade over this service, so existing
/// call sites keep working while new code logs through [LoggerService].
class LoggerService {
  LoggerService._();

  static final LoggerService instance = LoggerService._();

  /// Whether verbose (debug/info) logging is enabled.
  ///
  /// Always `false` in release/profile builds so production output only
  /// contains warnings, errors and critical entries.
  static bool get _verbose => kDebugMode;

  /// Single internal output sink for every emitted log line.
  ///
  /// Production defaults to the Dart developer log (never `print`/
  /// `debugPrint`); tests may replace it to capture output. Every `_emit`
  /// branch funnels through this one sink.
  @visibleForTesting
  static void Function(String line) outputSink = _defaultOutputSink;

  static void _defaultOutputSink(String line) => developer.log(line);

  /// Debug-level log — stripped from release builds.
  void debug(String message) => _emit(LogLevel.debug, message);

  /// Info-level log — stripped from release builds.
  void info(String message) => _emit(LogLevel.info, message);

  /// Warning-level log — emitted in all build modes.
  void warning(String message) => _emit(LogLevel.warning, message);

  /// Error-level log — emitted in all build modes.
  ///
  /// Only logs the exception [runtimeType] (never the raw exception string,
  /// which can embed sensitive values). Pass an optional [error] to include
  /// its runtime type, and an optional [stack] whose contents are appended
  /// in debug builds only. Stack details are always omitted from non-verbose
  /// (release/profile) logs, and any supplied stack content is passed
  /// through [sanitize] before emission so it cannot bypass redaction.
  void error(String message, [Object? error, StackTrace? stack]) =>
      _emit(LogLevel.error, message, error: error, stack: stack);

  /// Critical-level log — emitted in all build modes with the same privacy
  /// guarantees as [error].
  void critical(String message, [Object? error, StackTrace? stack]) =>
      _emit(LogLevel.critical, message, error: error, stack: stack);

  void _emit(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    final safeMessage = sanitize(message);
    final isVerbose = level == LogLevel.debug || level == LogLevel.info;
    if (isVerbose) {
      if (_verbose) outputSink('[CampusBite] $safeMessage');
      return;
    }
    if (_verbose) {
      final buffer = StringBuffer('[CampusBite][${level.name}] $safeMessage');
      if (error != null) buffer.write(' — ${error.runtimeType}');
      if (stack != null) buffer.write('\n${sanitize(stack.toString())}');
      outputSink('$buffer');
    } else {
      outputSink('[CampusBite][${level.name}] $safeMessage');
    }
  }

  /// Redacts known sensitive patterns from a caller-provided message before
  /// it can be emitted, so the documented guarantee holds even if a call site
  /// accidentally passes raw data (defense-in-depth).
  ///
  /// Currently strips: email addresses, JWT/FCM tokens, long opaque tokens,
  /// phone numbers, precise coordinate pairs, Firestore `users/<uid>` paths
  /// (UIDs 1–128 chars), and bare Firebase-style UIDs (20–128 chars).
  ///
  /// Limitation: arbitrary prose containing names or street addresses is not
  /// caught by pattern matching — call sites MUST still pass safe, static
  /// summaries and exceptions via the [error] parameter.
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

    // Long opaque tokens (e.g. FCM registration tokens, ~150+ chars) → [token].
    // Only tokens with an opaque mixed-character profile are redacted, so
    // long static technical identifiers are preserved.
    m = m.replaceAllMapped(
      RegExp(r'[A-Za-z0-9_-]{60,}'),
      (match) => _looksOpaque(match.group(0)!) ? '[token]' : match.group(0)!,
    );

    // Bare Firebase-style UIDs (20–128-char opaque base64url tokens, not
    // inside a users/ path) → [uid]. Catches Firestore auto-IDs, Firebase
    // Auth UIDs and custom UIDs. An opaque mixed-character profile is
    // required, so readable static labels such as `firebase_crashlytics`
    // (single lowercase class) are preserved while genuine mixed-case
    // tokens are redacted.
    m = m.replaceAllMapped(
      RegExp(r'(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{20,128}(?![A-Za-z0-9_-])'),
      (match) => _looksOpaque(match.group(0)!) ? '[uid]' : match.group(0)!,
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

  /// Whether [value] looks like an opaque generated identifier rather than a
  /// readable static label. Opaque identifiers mix at least two character
  /// classes among uppercase, lowercase and digits; a single-class label such
  /// as `firebase_crashlytics` (lowercase + separators only) is preserved.
  static bool _looksOpaque(String value) {
    var classes = 0;
    if (RegExp(r'[A-Z]').hasMatch(value)) classes++;
    if (RegExp(r'[a-z]').hasMatch(value)) classes++;
    if (RegExp(r'[0-9]').hasMatch(value)) classes++;
    return classes >= 2;
  }
}
