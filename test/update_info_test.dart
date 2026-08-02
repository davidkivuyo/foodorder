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

import 'package:campusbite/models/update_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareVersions', () {
    test('equal versions compare as 0', () {
      expect(compareVersions('1.4.2', '1.4.2'), 0);
      expect(compareVersions('1.0.0+3', '1.0.0+1'), 0);
    });

    test('newer version compares greater than older', () {
      expect(compareVersions('1.4.2', '1.4.1'), 1);
      expect(compareVersions('1.10.0', '1.9.0'), 1);
      expect(compareVersions('2.0.0', '1.99.99'), 1);
    });

    test('older version compares less than newer', () {
      expect(compareVersions('1.4.1', '1.4.2'), -1);
      expect(compareVersions('1.9.0', '1.10.0'), -1);
    });

    test('shorter version is treated as older', () {
      expect(compareVersions('1.4', '1.4.0'), 0);
      expect(compareVersions('1.4', '1.4.1'), -1);
    });
  });

  group('UpdateInfo.fromJson', () {
    test('parses all known fields', () {
      final info = UpdateInfo.fromJson({
        'version': '1.4.2',
        'minimumVersion': '1.2.0',
        'forceUpdate': true,
        'releaseNotes': 'Bug fixes.',
        'downloads': {
          'universal': 'https://dl.larason.space/v1.4.2/app.apk',
          'arm64-v8a': 'https://dl.larason.space/v1.4.2/app-arm.apk',
        },
        'checksums': {
          'universal': 'https://dl.larason.space/v1.4.2/app.apk.sha256',
        },
      });

      expect(info.version, '1.4.2');
      expect(info.minimumVersion, '1.2.0');
      expect(info.forceUpdate, isTrue);
      expect(info.releaseNotes, 'Bug fixes.');
      expect(info.downloads.length, 2);
      expect(info.checksums['universal'],
          'https://dl.larason.space/v1.4.2/app.apk.sha256');
      expect(info.stale, isFalse);
    });

    test('unknown/future fields are preserved untouched', () {
      final info = UpdateInfo.fromJson({
        'version': '1.4.2',
        'minimumVersion': '1.2.0',
        'forceUpdate': false,
        'releaseNotes': '',
        'downloads': const {},
        'checksums': const {},
        'channel': 'beta',
        'rolloutPercentage': 25,
        'extraNested': {'a': 1},
      });

      expect(info.raw['channel'], 'beta');
      expect(info.raw['rolloutPercentage'], 25);
      expect((info.raw['extraNested'] as Map)['a'], 1);
    });

    test('stale flag is captured', () {
      final info = UpdateInfo.fromJson({
        'version': '1.4.2',
        'minimumVersion': '1.2.0',
        'forceUpdate': false,
        'releaseNotes': '',
        'downloads': const {},
        'checksums': const {},
        'stale': true,
      });
      expect(info.stale, isTrue);
    });

    test('missing fields fall back to safe defaults', () {
      final info = UpdateInfo.fromJson(const {});
      expect(info.version, '');
      expect(info.minimumVersion, '');
      expect(info.forceUpdate, isFalse);
      expect(info.releaseNotes, '');
      expect(info.downloads, isEmpty);
      expect(info.checksums, isEmpty);
    });
  });

  group('UpdateInfo.toJson round-trip', () {
    test('preserves unknown fields through serialization', () {
      final original = UpdateInfo.fromJson({
        'version': '1.4.2',
        'minimumVersion': '1.2.0',
        'forceUpdate': false,
        'releaseNotes': '',
        'downloads': const {},
        'checksums': const {},
        'channel': 'beta',
      });
      final roundTripped = UpdateInfo.fromJson(original.toJson());
      expect(roundTripped.raw['channel'], 'beta');
      expect(roundTripped.version, '1.4.2');
    });
  });
}
