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
import 'package:campusbite/services/version_comparator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VersionComparator.isNewer', () {
    test('MINOR differs — the known-working case', () {
      expect(
        VersionComparator.isNewer(local: '1.0.0-dev', remote: '1.1.0-dev'),
        isTrue,
      );
    });

    test('numeric identifier comparison, not string comparison', () {
      expect(
        VersionComparator.isNewer(local: '1.0.9-dev', remote: '1.0.10-dev'),
        isTrue,
      );
      expect(
        VersionComparator.isNewer(local: '1.0.10-dev', remote: '1.0.9-dev'),
        isFalse,
      );
    });

    test('bare release beats pre-release at the same core version', () {
      expect(
        VersionComparator.isNewer(local: '1.0.0-dev', remote: '1.0.0'),
        isTrue,
      );
      expect(
        VersionComparator.isNewer(local: '1.0.0', remote: '1.0.0-dev'),
        isFalse,
      );
    });

    test('identical versions are not newer', () {
      expect(
        VersionComparator.isNewer(local: '1.0.0-dev', remote: '1.0.0-dev'),
        isFalse,
      );
    });

    test('numeric pre-release sub-identifier comparison', () {
      expect(
        VersionComparator.isNewer(local: '1.0.0-dev.1', remote: '1.0.0-dev.2'),
        isTrue,
      );
    });

    test('alphabetic pre-release identifier comparison', () {
      expect(
        VersionComparator.isNewer(local: '1.0.0-alpha', remote: '1.0.0-beta'),
        isTrue,
      );
    });

    test('leading v is stripped before parsing', () {
      expect(
        VersionComparator.isNewer(local: 'v1.0.0-dev', remote: 'v1.1.0-dev'),
        isTrue,
      );
    });

    test('build metadata is precedence-neutral in both directions', () {
      expect(
        VersionComparator.isNewer(local: '1.0.0+1', remote: '1.0.0+3'),
        isFalse,
      );
      expect(
        VersionComparator.isNewer(local: '1.0.0+3', remote: '1.0.0+1'),
        isFalse,
      );
      expect(
        VersionComparator.isNewer(local: '1.0.0-dev+1', remote: '1.0.0-dev+2'),
        isFalse,
      );
    });

    test('malformed input throws a typed exception (never string compare)', () {
      expect(
        () => VersionComparator.isNewer(local: 'not-a-version', remote: '1.0.0'),
        throwsA(isA<VersionParseException>()),
      );
      expect(
        () => VersionComparator.isNewer(local: '1.0.0', remote: 'garbage'),
        throwsA(isA<VersionParseException>()),
      );
      expect(
        () => VersionComparator.isNewer(local: '1.4', remote: '1.4.0'),
        throwsA(isA<VersionParseException>()),
      );
    });
  });

  group('VersionComparator.isBelowMinimum', () {
    test('older core version is below the minimum', () {
      expect(
        VersionComparator.isBelowMinimum(local: '1.0.0-dev', minimum: '1.1.0-dev'),
        isTrue,
      );
      expect(
        VersionComparator.isBelowMinimum(local: '1.0.9-dev', minimum: '1.0.10-dev'),
        isTrue,
      );
      expect(
        VersionComparator.isBelowMinimum(local: '1.0.10-dev', minimum: '1.0.9-dev'),
        isFalse,
      );
    });

    test('pre-release is below a bare release at the same core version', () {
      expect(
        VersionComparator.isBelowMinimum(local: '1.0.0-dev', minimum: '1.0.0'),
        isTrue,
      );
      expect(
        VersionComparator.isBelowMinimum(local: '1.0.0', minimum: '1.0.0-dev'),
        isFalse,
      );
    });

    test('equal versions are not below the minimum', () {
      expect(
        VersionComparator.isBelowMinimum(local: '1.0.0-dev', minimum: '1.0.0-dev'),
        isFalse,
      );
      expect(
        VersionComparator.isBelowMinimum(local: '1.0.0', minimum: '1.0.0'),
        isFalse,
      );
    });

    test('pre-release identifier ordering applies to minimums', () {
      expect(
        VersionComparator.isBelowMinimum(local: '1.0.0-alpha', minimum: '1.0.0-beta'),
        isTrue,
      );
      expect(
        VersionComparator.isBelowMinimum(local: '1.0.0-dev.1', minimum: '1.0.0-dev.2'),
        isTrue,
      );
    });

    test('leading v is stripped before parsing', () {
      expect(
        VersionComparator.isBelowMinimum(local: 'v1.0.0-dev', minimum: 'v1.1.0-dev'),
        isTrue,
      );
    });

    test('build metadata is precedence-neutral for minimums', () {
      expect(
        VersionComparator.isBelowMinimum(local: '1.0.0+1', minimum: '1.0.0+3'),
        isFalse,
      );
      expect(
        VersionComparator.isBelowMinimum(local: '1.0.0+3', minimum: '1.0.0+1'),
        isFalse,
      );
    });

    test('malformed input throws a typed exception', () {
      expect(
        () => VersionComparator.isBelowMinimum(local: 'not-a-version', minimum: '1.0.0'),
        throwsA(isA<VersionParseException>()),
      );
      expect(
        () => VersionComparator.isBelowMinimum(local: '1.0.0', minimum: 'garbage'),
        throwsA(isA<VersionParseException>()),
      );
    });
  });

  group('UpdateService.decideState — end-to-end decision flow', () {
    // The manually-verified case, exercised through the actual decision point
    // the app uses, not just the comparator in isolation.
    test('v1.0.0-dev local → v1.1.0-dev remote still offers an update', () {
      final state = UpdateService.decideState(
        current: 'v1.0.0-dev',
        remoteVersion: 'v1.1.0-dev',
        minimumVersion: 'v1.0.0-dev',
        forceUpdate: false,
      );
      expect(state, UpdateState.updateAvailable);
    });

    test('at/above remote version yields no update', () {
      expect(
        UpdateService.decideState(
          current: '1.1.0-dev',
          remoteVersion: '1.1.0-dev',
          minimumVersion: '1.0.0-dev',
          forceUpdate: false,
        ),
        UpdateState.current,
      );
      expect(
        UpdateService.decideState(
          current: '1.0.10-dev',
          remoteVersion: '1.0.9-dev',
          minimumVersion: '1.0.0',
          forceUpdate: false,
        ),
        UpdateState.current,
      );
    });

    test('below minimum forces an update even when remote equals local', () {
      expect(
        UpdateService.decideState(
          current: '1.0.0',
          remoteVersion: '1.0.0',
          minimumVersion: '1.5.0',
          forceUpdate: false,
        ),
        UpdateState.updateRequired,
      );
    });

    test('forceUpdate flag always mandates the update', () {
      expect(
        UpdateService.decideState(
          current: '9.9.9',
          remoteVersion: '1.0.0',
          minimumVersion: '1.0.0',
          forceUpdate: true,
        ),
        UpdateState.updateRequired,
      );
    });

    test('differing build metadata alone never triggers an update', () {
      expect(
        UpdateService.decideState(
          current: '1.0.0+1',
          remoteVersion: '1.0.0+3',
          minimumVersion: '1.0.0+1',
          forceUpdate: false,
        ),
        UpdateState.current,
      );
    });

    test('malformed local version fails safe to current (no crash)', () {
      expect(
        UpdateService.decideState(
          current: 'not-a-version',
          remoteVersion: '1.0.0',
          minimumVersion: '1.0.0',
          forceUpdate: false,
        ),
        UpdateState.current,
      );
    });

    test('malformed remote version fails safe to current (no crash)', () {
      expect(
        UpdateService.decideState(
          current: '1.0.0',
          remoteVersion: 'garbage',
          minimumVersion: '1.0.0',
          forceUpdate: false,
        ),
        UpdateState.current,
      );
    });

    test('malformed minimum version fails safe to current (no crash)', () {
      expect(
        UpdateService.decideState(
          current: '1.0.0',
          remoteVersion: '1.0.0',
          minimumVersion: 'garbage',
          forceUpdate: false,
        ),
        UpdateState.current,
      );
    });

    // Backward-compat guard: every version pair the old compareVersions tests
    // covered must still produce the same update *decision*.
    test('existing numeric-only cases keep their decisions', () {
      expect(
        UpdateService.decideState(
          current: '1.4.2',
          remoteVersion: '1.4.2',
          minimumVersion: '1.0.0',
          forceUpdate: false,
        ),
        UpdateState.current,
      );
      expect(
        UpdateService.decideState(
          current: '1.4.1',
          remoteVersion: '1.4.2',
          minimumVersion: '1.0.0',
          forceUpdate: false,
        ),
        UpdateState.updateAvailable,
      );
      expect(
        UpdateService.decideState(
          current: '1.10.0',
          remoteVersion: '1.9.0',
          minimumVersion: '1.0.0',
          forceUpdate: false,
        ),
        UpdateState.current,
      );
      expect(
        UpdateService.decideState(
          current: '1.9.0',
          remoteVersion: '1.10.0',
          minimumVersion: '1.0.0',
          forceUpdate: false,
        ),
        UpdateState.updateAvailable,
      );
      expect(
        UpdateService.decideState(
          current: '2.0.0',
          remoteVersion: '1.99.99',
          minimumVersion: '1.0.0',
          forceUpdate: false,
        ),
        UpdateState.current,
      );
      expect(
        UpdateService.decideState(
          current: '1.0.0+3',
          remoteVersion: '1.0.0+1',
          minimumVersion: '1.0.0',
          forceUpdate: false,
        ),
        UpdateState.current,
      );
    });
  });
}
