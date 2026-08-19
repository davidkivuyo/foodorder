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

import 'dart:convert';

import 'package:campusbite/models/update_info.dart';
import 'package:campusbite/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression tests for the stale-while-revalidate update check.
///
/// The bug being locked in: `checkForUpdate()` used to apply a still-valid
/// (< 12h TTL) cached metadata response and return WITHOUT contacting the
/// server. A release published after the cache was written was therefore
/// invisible until the cache lapsed — and on devices whose process was never
/// cold-started after expiry, forever (only an app-data erase "fixed" it).
///
/// The fix: the cache is a fast path and an offline fallback only; every
/// check revalidates against the endpoint and applies the fresh verdict.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Reset the shared singleton (check/download state, busy flag) so no
    // test inherits a leftover state — important now that checkForUpdate
    // preserves an active download/install flow instead of overwriting it.
    UpdateService.instance.debugResetForTest();
    // Bypass the Android-only platform gate (false on the VM test runner).
    UpdateService.debugForceCheckEnabled = true;
    UpdateService.debugLatestFetcher = null;
    PackageInfo.setMockInitialValues(
      appName: 'Campus Bite',
      packageName: 'com.example.campusbite',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(() {
    UpdateService.debugForceCheckEnabled = false;
    UpdateService.debugLatestFetcher = null;
  });

  UpdateInfo info({
    String version = '1.0.0',
    String minimumVersion = '1.0.0',
    bool forceUpdate = false,
  }) {
    return UpdateInfo(
      version: version,
      minimumVersion: minimumVersion,
      forceUpdate: forceUpdate,
      releaseNotes: 'Notes',
      downloads: {
        'universal': 'https://dl.larason.space/v1.0.0/app.apk',
      },
      checksums: {
        'universal': 'https://dl.larason.space/v1.0.0/app.apk.sha256',
      },
      stale: false,
    );
  }

  Future<void> seedCache({
    String version = '1.0.0',
    String minimumVersion = '1.0.0',
    int? cachedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'update_metadata_cache',
      jsonEncode(info(version: version, minimumVersion: minimumVersion).toJson()),
    );
    await prefs.setInt(
      'update_metadata_cached_at',
      cachedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('update_metadata_cache');
    await prefs.remove('update_metadata_cached_at');
    await prefs.remove('update_dismissed_version');
  }

  test('fresh cache with an older version does NOT suppress a newer server '
      'release — the check still revalidates', () async {
    SharedPreferences.setMockInitialValues({});
    await seedCache(version: '1.0.0'); // fresh, says app is current
    UpdateService.debugLatestFetcher = () async => info(version: '1.1.0');

    await UpdateService.instance.checkForUpdate();

    // Regression: before the fix this returned UpdateState.current because
    // the fresh cache was trusted without contacting the server.
    expect(UpdateService.instance.state, UpdateState.updateAvailable);
  });

  test('fresh cache with the same version as the server stays current', () async {
    SharedPreferences.setMockInitialValues({});
    await seedCache(version: '1.0.0');
    UpdateService.debugLatestFetcher = () async => info(version: '1.0.0');

    await UpdateService.instance.checkForUpdate();

    expect(UpdateService.instance.state, UpdateState.current);
  });

  test('a dismissed optional update is respected by the revalidation — same '
      'version does not re-prompt', () async {
    // Local is older than the cached/server version, so the cached metadata
    // alone would offer an update; the persisted dismissal suppresses it and
    // the revalidation must not resurrect the prompt for the same version.
    PackageInfo.setMockInitialValues(
      appName: 'Campus Bite',
      packageName: 'com.example.campusbite',
      version: '0.9.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    await seedCache(version: '1.0.0', minimumVersion: '0.8.0');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('update_dismissed_version', '1.0.0');
    UpdateService.debugLatestFetcher =
        () async => info(version: '1.0.0', minimumVersion: '0.8.0');

    await UpdateService.instance.checkForUpdate();

    expect(UpdateService.instance.state, UpdateState.current);
    expect(UpdateService.instance.dismissed, isTrue);
  });

  test('a dismissed older version does not suppress a NEWER release — '
      'revalidation re-prompts', () async {
    PackageInfo.setMockInitialValues(
      appName: 'Campus Bite',
      packageName: 'com.example.campusbite',
      version: '0.9.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    await seedCache(version: '1.0.0', minimumVersion: '0.8.0');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('update_dismissed_version', '1.0.0');
    UpdateService.debugLatestFetcher =
        () async => info(version: '1.1.0', minimumVersion: '0.8.0');

    await UpdateService.instance.checkForUpdate();

    // The persisted dismissal is keyed to 1.0.0; the fresh server metadata
    // says 1.1.0, so the prompt must reappear.
    expect(UpdateService.instance.state, UpdateState.updateAvailable);
    expect(UpdateService.instance.dismissed, isFalse);
  });

  test('expired cache still revalidates and surfaces a newer release', () async {
    SharedPreferences.setMockInitialValues({});
    final expired = DateTime.now()
        .subtract(const Duration(hours: 13))
        .millisecondsSinceEpoch;
    await seedCache(version: '1.0.0', cachedAt: expired);
    UpdateService.debugLatestFetcher = () async => info(version: '1.1.0');

    await UpdateService.instance.checkForUpdate();

    expect(UpdateService.instance.state, UpdateState.updateAvailable);
  });

  test('network failure with a fresh cache keeps the cached verdict', () async {
    SharedPreferences.setMockInitialValues({});
    await seedCache(version: '1.0.0');
    UpdateService.debugLatestFetcher = () async => null; // fetch failed

    await UpdateService.instance.checkForUpdate();

    // No crash, no spurious update — the cached decision is preserved.
    expect(UpdateService.instance.state, UpdateState.current);
  });

  test('network failure with no cache falls back to current, not a crash',
      () async {
    SharedPreferences.setMockInitialValues({});
    await clearCache();
    UpdateService.debugLatestFetcher = () async => null;

    await UpdateService.instance.checkForUpdate();

    expect(UpdateService.instance.state, UpdateState.current);
  });

  test('a THROWN revalidation keeps a cached mandatory-update verdict',
      () async {
    SharedPreferences.setMockInitialValues({});
    // Cached metadata forces an update (local 1.0.0 is below minimum 2.0.0),
    // so the blocking screen is already up when the refresh throws.
    await seedCache(version: '1.0.0', minimumVersion: '2.0.0');
    UpdateService.debugLatestFetcher = () async =>
        throw Exception('revalidation failed');

    await UpdateService.instance.checkForUpdate();

    // The cached mandatory verdict must survive a thrown refresh: the app
    // stays blocked until the update is performed and is never downgraded to
    // `current` by a transient network error.
    expect(UpdateService.instance.state, UpdateState.updateRequired);
  });

  test('a check while a download flow is active preserves the flow — no '
      'checking, no cached-verdict clobber', () async {
    SharedPreferences.setMockInitialValues({});
    // If applied, this cached metadata would force an update (local 1.0.0 is
    // below minimum 2.0.0) — proof the cached apply is skipped for flows.
    await seedCache(version: '1.0.0', minimumVersion: '2.0.0');
    UpdateService.debugLatestFetcher = () async => null; // fetch fails
    UpdateService.instance.debugSetStateForTest(UpdateState.downloading);

    await UpdateService.instance.checkForUpdate();

    // Neither `checking`, nor the cached mandatory verdict, nor the offline
    // fallback clobbered the running flow.
    expect(UpdateService.instance.state, UpdateState.downloading);
  });

  test('a flow started during revalidation is not clobbered by fresh '
      'metadata', () async {
    SharedPreferences.setMockInitialValues({});
    UpdateService.debugLatestFetcher = () async {
      // Simulate the user tapping "Update now" on the prompt while the
      // revalidation is in flight.
      UpdateService.instance.debugSetStateForTest(UpdateState.downloading);
      return info(version: '1.1.0'); // would apply updateAvailable unguarded
    };

    await UpdateService.instance.checkForUpdate();

    // The fresh metadata is cached but not applied — the newly started
    // download owns the state.
    expect(UpdateService.instance.state, UpdateState.downloading);
  });

  test('a check while failed re-applies a fresh verdict so the user can '
      'retry', () async {
    SharedPreferences.setMockInitialValues({});
    await clearCache();
    UpdateService.debugLatestFetcher = () async => info(version: '1.1.0');
    UpdateService.instance.debugSetStateForTest(UpdateState.failed);

    await UpdateService.instance.checkForUpdate();

    // `failed` is NOT a running flow — the fresh verdict must surface so the
    // user is not stranded on the failure screen.
    expect(UpdateService.instance.state, UpdateState.updateAvailable);
  });

  test('isFlowActiveState covers the download/install flow but not failed',
      () {
    expect(UpdateService.isFlowActiveState(UpdateState.downloading), isTrue);
    expect(UpdateService.isFlowActiveState(UpdateState.paused), isTrue);
    expect(UpdateService.isFlowActiveState(UpdateState.verifying), isTrue);
    expect(UpdateService.isFlowActiveState(UpdateState.readyToInstall), isTrue);
    expect(
        UpdateService.isFlowActiveState(UpdateState.installPermissionRequired),
        isTrue);
    expect(UpdateService.isFlowActiveState(UpdateState.installing), isTrue);
    expect(UpdateService.isFlowActiveState(UpdateState.installed), isTrue);
    expect(UpdateService.isFlowActiveState(UpdateState.failed), isFalse);
    expect(UpdateService.isFlowActiveState(UpdateState.updateAvailable), isFalse);
    expect(UpdateService.isFlowActiveState(UpdateState.updateRequired), isFalse);
    expect(UpdateService.isFlowActiveState(UpdateState.checking), isFalse);
    expect(UpdateService.isFlowActiveState(UpdateState.current), isFalse);
    expect(UpdateService.isFlowActiveState(UpdateState.idle), isFalse);
  });
}
