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

import 'package:campusbite/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateService.isAllowedDownloadUrl', () {
    test('accepts https URLs on the allowed host only', () {
      expect(UpdateService.isAllowedDownloadUrl(
              'https://dl.larason.space/v1.4.2/app.apk'),
          isTrue);
      expect(UpdateService.isAllowedDownloadUrl(
              'https://dl.larason.space/v1.4.2/app.apk.sha256'),
          isTrue);
    });

    test('rejects other hosts', () {
      expect(UpdateService.isAllowedDownloadUrl(
              'https://github.com/owner/repo/releases/download/v1/app.apk'),
          isFalse);
      expect(UpdateService.isAllowedDownloadUrl(
              'https://dl.larason.space.evil.com/app.apk'),
          isFalse);
      expect(
          UpdateService.isAllowedDownloadUrl('https://evil.com/app.apk'),
          isFalse);
      expect(UpdateService.isAllowedDownloadUrl('http://dl.larason.space/a'),
          isFalse);
    });

    test('rejects non-URL strings', () {
      expect(UpdateService.isAllowedDownloadUrl(''), isFalse);
      expect(UpdateService.isAllowedDownloadUrl('not a url'), isFalse);
      expect(UpdateService.isAllowedDownloadUrl('ftp://dl.larason.space/a'),
          isFalse);
    });
  });

  group('UpdateService.resolveRedirect', () {
    const base = 'https://dl.larason.space/v1.4.2/CampusBite-universal.apk';

    test('resolves a relative location against the current hop', () {
      expect(
        UpdateService.resolveRedirect('/v1.4.2/CampusBite-arm64-v8a.apk', base),
        'https://dl.larason.space/v1.4.2/CampusBite-arm64-v8a.apk',
      );
      expect(
        UpdateService.resolveRedirect('app.apk', base),
        'https://dl.larason.space/v1.4.2/app.apk',
      );
      expect(
        UpdateService.resolveRedirect(
            '/v1.4.2/CampusBite-universal.apk.sha256', base),
        'https://dl.larason.space/v1.4.2/CampusBite-universal.apk.sha256',
      );
    });

    test('passes through an absolute location on the allowed host', () {
      expect(
        UpdateService.resolveRedirect(
            'https://dl.larason.space/v1.4.2/CampusBite-x86_64.apk', base),
        'https://dl.larason.space/v1.4.2/CampusBite-x86_64.apk',
      );
    });

    test('rejects a relative redirect resolving to a different host', () {
      expect(UpdateService.resolveRedirect('//evil.com/app.apk', base),
          isNull);
      expect(
        UpdateService.resolveRedirect(
            'https://evil.com/app.apk', base),
        isNull,
      );
      expect(UpdateService.resolveRedirect('http://dl.larason.space/app.apk', base),
          isNull);
    });

    test('rejects a relative redirect resolving off the allowed path host', () {
      expect(
        UpdateService.resolveRedirect(
            '/v1.4.2/app.apk', 'https://dl.larason.space.evil.com/app.apk'),
        isNull,
      );
      expect(UpdateService.resolveRedirect('//evil.com/app.apk', base),
          isNull);
    });
  });
}
