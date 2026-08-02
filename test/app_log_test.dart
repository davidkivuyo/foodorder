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
import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/services/app_log.dart';

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
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      originalDebugPrint = debugPrint;
      captured.clear();
      debugPrint = (String? message, {int? wrapWidth}) {
        captured.add(message ?? '');
      };
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
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
