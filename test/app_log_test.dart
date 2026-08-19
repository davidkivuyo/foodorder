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

import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/services/app_log.dart';
import 'package:campusbite/services/logger_service.dart';

void main() {
  group('AppLog.sanitize — sensitive data categories', () {
    test('redacts email addresses', () {
      final out = AppLog.sanitize('Contact jane.doe@example.com for help');
      expect(out, 'Contact [email] for help');
    });

    test('redacts JWT tokens', () {
      const token =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.'
          'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
      final out = AppLog.sanitize('Token: $token');
      expect(out, 'Token: [token]');
    });

    test('redacts long opaque tokens (FCM registration tokens)', () {
      const token =
          'fcmABCdefGHIjklMNOpqrSTUvwxYZ0123456789_abCDefGHIJKLMNop'
          'QRStuvWXyz0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKL'
          'MNOPQRSTUVWXYZ0123456789';
      final out = AppLog.sanitize('Token: $token');
      expect(out, 'Token: [token]');
    });

    test('redacts bare Firebase-style UIDs', () {
      const uid = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ12';
      final out = AppLog.sanitize('user $uid failed');
      expect(out, 'user [uid] failed');
    });

    test('redacts phone numbers (international and local)', () {
      const international = '+254712345678';
      const local = '0712345678';
      final out = AppLog.sanitize('Call $international or $local today');
      expect(out, 'Call [phone] or [phone] today');
    });

    test('redacts phone numbers with parenthesized area codes', () {
      final out = AppLog.sanitize('Call (415) 555-2671 today');
      expect(out, 'Call [phone] today');
    });

    test('redacts precise coordinate pairs', () {
      final out = AppLog.sanitize('Location 39.2083, -6.7924');
      expect(out, 'Location [coordinates]');
    });

    test('redacts Firestore user document paths', () {
      const path = 'users/ABCDEFGHIJKLMNOPQRSTUVWXYZ12';
      final out = AppLog.sanitize('Doc $path updated');
      expect(out, 'Doc users/[id] updated');
    });

    test('redacts Firestore paths with short custom UIDs', () {
      const path = 'users/customUid12345';
      final out = AppLog.sanitize('Doc $path updated');
      expect(out, 'Doc users/[id] updated');
    });

    test('redacts users paths with short custom UIDs (1 char)', () {
      final out = AppLog.sanitize('Doc users/a updated');
      expect(out, 'Doc users/[id] updated');
    });

    test('redacts users paths with 128-char custom UIDs', () {
      final uid = 'A' * 128;
      final out = AppLog.sanitize('Doc users/$uid updated');
      expect(out, 'Doc users/[id] updated');
    });

    test('redacts users paths with dashes and underscores in the UID', () {
      const path = 'users/custom-user_1A';
      final out = AppLog.sanitize('Doc $path updated');
      expect(out, 'Doc users/[id] updated');
    });

    test('redacts bare 20-char opaque UIDs', () {
      const uid = 'abcdefghij0123456789';
      final out = AppLog.sanitize('user $uid failed');
      expect(out, 'user [uid] failed');
    });

    test('preserves static technical labels like firebase_crashlytics', () {
      // Explicitly allowlisted in _trustedTechnicalLabels (static plugin
      // name), so it is preserved despite matching the bare-identifier regex.
      final out = AppLog.sanitize('plugin firebase_crashlytics initialized');
      expect(out, 'plugin firebase_crashlytics initialized');
    });

    test('redacts single-class lowercase bare identifiers (not allowlisted)', () {
      // 20 lowercase chars — a single character class, no allowlist entry.
      // Firestore auto-IDs are [a-z0-9]{20}, so this must be redacted like
      // any other UID.
      const id = 'abcdefghijklmnopqrst';
      expect(id.length, 20);
      final out = AppLog.sanitize('user $id failed');
      expect(out, 'user [uid] failed');
    });

    test('preserves long lowercase technical identifiers', () {
      // Lowercase + separators only, >128 chars — beyond the bare-UID range
      // (20–128), so the long-token rule's single-class heuristic keeps it
      // readable instead of redacting it.
      const label =
          'com_example_flutter_application_phase_seventeen_monitoring_module_'
          'with_longer_technical_context_for_emission_testing_and_extra_context';
      expect(label.length, greaterThan(128));
      final out = AppLog.sanitize('module $label loaded');
      expect(out, 'module $label loaded');
    });
  });

  group('AppLog.sanitize — unsafe free-form input', () {
    test('redacts every sensitive category embedded in one message', () {
      const raw =
          'email a@b.com, jwt '
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.'
          'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c, '
          'uid ABCDEFGHIJKLMNOPQRSTUVWXYZ12, '
          'phone +254712345678, coords 39.2083, -6.7924, '
          'path users/ABCDEFGHIJKLMNOPQRSTUVWXYZ12';
      final out = AppLog.sanitize(raw);
      expect(
        out,
        'email [email], jwt [token], uid [uid], '
        'phone [phone], coords [coordinates], path users/[id]',
      );
    });

    test('preserves safe prose unchanged', () {
      const safe = 'Order placed successfully';
      expect(AppLog.sanitize(safe), safe);
    });
  });

  group('AppLog emission behavior', () {
    final captured = <String>[];
    late void Function(String) originalSink;

    setUp(() {
      originalSink = LoggerService.outputSink;
      captured.clear();
      LoggerService.outputSink = captured.add;
    });

    tearDown(() {
      LoggerService.outputSink = originalSink;
    });

    test(
      'error logs emit exception runtimeType but never the raw error string',
      () {
        final secret = 'sensitive internal detail';
        AppLog.e('[AppLogTest] failure', StateError(secret));
        final joined = captured.join('\n');
        expect(joined, contains('StateError'));
        expect(joined, isNot(contains(secret)));
      },
    );

    test('free-form values are sanitized before emission', () {
      AppLog.d('user ABCDEFGHIJKLMNOPQRSTUVWXYZ12 logged in');
      final joined = captured.join('\n');
      expect(joined, contains('[uid]'));
      expect(joined, isNot(contains('ABCDEFGHIJKLMNOPQRSTUVWXYZ12')));
    });
  });
}
