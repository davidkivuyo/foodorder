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
import 'package:campusbite/services/input_validator.dart';

/// Phase 15 — Part 6 (input validation).
void main() {
  group('InputValidator.sanitizeName', () {
    test('trims surrounding whitespace', () {
      expect(InputValidator.sanitizeName('  John Doe  '), 'John Doe');
    });

    test('collapses repeated internal whitespace', () {
      expect(InputValidator.sanitizeName('John   Doe'), 'John Doe');
    });

    test('rejects names containing control characters (log-injection vector)',
        () {
      // Phase 15 — Part 6: control characters are a validation failure, not
      // something to silently strip and persist.
      expect(InputValidator.sanitizeName('John\u0000Doe\u001b[31m'), isEmpty);
      expect(InputValidator.sanitizeName('John\u0000Doe'), isEmpty);
    });

    test('rejects names exceeding the rules-enforced 100-char limit', () {
      final long = 'A' * 250;
      expect(InputValidator.sanitizeName(long), isEmpty);
    });

    test('preserves names at exactly the maximum length', () {
      final exact = 'A' * InputValidator.maxNameLength;
      expect(InputValidator.sanitizeName(exact), exact);
    });

    test('returns empty string for blank input', () {
      expect(InputValidator.sanitizeName('   '), isEmpty);
      expect(InputValidator.sanitizeName(null), isEmpty);
    });
  });

  group('InputValidator.sanitizeEmail', () {
    test('trims surrounding whitespace', () {
      expect(InputValidator.sanitizeEmail('  a@b.com  '), 'a@b.com');
    });

    test('rejects emails containing control characters', () {
      // Phase 15 — Part 6: a modified address must never be persisted.
      expect(InputValidator.sanitizeEmail('a\u0000b@example.com'), isEmpty);
      expect(InputValidator.sanitizeEmail('user\u0085@example.com'), isEmpty);
    });

    test('returns empty string for null or blank input', () {
      expect(InputValidator.sanitizeEmail('   '), isEmpty);
      expect(InputValidator.sanitizeEmail(null), isEmpty);
    });

    test('preserves valid addresses unchanged', () {
      expect(InputValidator.sanitizeEmail('student@campus.ac.tz'),
          'student@campus.ac.tz');
    });
  });

  group('InputValidator.isValidEmail', () {
    test('accepts standard addresses', () {
      expect(InputValidator.isValidEmail('student@campus.ac.tz'), isTrue);
      expect(InputValidator.isValidEmail('a.b+c@example.co.uk'), isTrue);
    });

    test('rejects malformed addresses', () {
      expect(InputValidator.isValidEmail('not-an-email'), isFalse);
      expect(InputValidator.isValidEmail('a@b'), isFalse);
      expect(InputValidator.isValidEmail(''), isFalse);
      expect(InputValidator.isValidEmail(null), isFalse);
      expect(InputValidator.isValidEmail('a@b@c.com'), isFalse);
    });

    test('rejects over-long addresses', () {
      final tooLong = '${'a' * 320}@example.com';
      expect(InputValidator.isValidEmail(tooLong), isFalse);
    });

    test('rejects addresses containing Unicode control characters', () {
      // NUL and C1 controls (e.g. NEL \u0085) are not whitespace, so they
      // would otherwise slip past the email regex character class.
      expect(InputValidator.isValidEmail('a\u0000b@example.com'), isFalse);
      expect(InputValidator.isValidEmail('user\u0085@example.com'), isFalse);
    });
  });

  group('InputValidator.isValidPhone', () {
    test('accepts international and local formats', () {
      expect(InputValidator.isValidPhone('+255712345678'), isTrue);
      expect(InputValidator.isValidPhone('0712 345 678'), isTrue);
      expect(InputValidator.isValidPhone('+1 (415) 555-2671'), isTrue);
    });

    test('rejects alphabetic and malformed values', () {
      expect(InputValidator.isValidPhone('call me'), isFalse);
      expect(InputValidator.isValidPhone('123'), isFalse);
      expect(InputValidator.isValidPhone(''), isFalse);
      expect(InputValidator.isValidPhone(null), isFalse);
    });

    test('rejects separator-only values (no digits)', () {
      expect(InputValidator.isValidPhone('--- ---'), isFalse);
      expect(InputValidator.isValidPhone('( ) - ( )'), isFalse);
    });

    test('rejects control characters including newlines and tabs', () {
      expect(InputValidator.isValidPhone('0712\n345678'), isFalse);
      expect(InputValidator.isValidPhone('0712\t345678'), isFalse);
      expect(InputValidator.isValidPhone('0712\u0000345678'), isFalse);
    });

    test('rejects repeated or unbalanced separators', () {
      expect(InputValidator.isValidPhone('07--12345678'), isFalse);
      expect(InputValidator.isValidPhone('0712  345678'), isFalse);
      expect(InputValidator.isValidPhone('0712)345678'), isFalse);
    });

    test('rejects too few or too many digits', () {
      expect(InputValidator.isValidPhone('123456'), isFalse);
      expect(InputValidator.isValidPhone('1234567890123456'), isFalse);
    });
  });

  group('InputValidator control-character handling', () {
    test('detects control characters', () {
      expect(InputValidator.containsControlCharacters('a\u0007b'), isTrue);
      expect(InputValidator.containsControlCharacters('normal text'), isFalse);
      expect(InputValidator.containsControlCharacters(null), isFalse);
    });

    test('strips C0 and C1 control characters', () {
      expect(InputValidator.stripControlCharacters('a\u0000b'), 'ab');
      expect(InputValidator.stripControlCharacters('a\u009Fb'), 'ab');
      expect(InputValidator.stripControlCharacters('plain'), 'plain');
    });
  });
}
