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

import 'package:campusbite/main.dart';
import 'package:campusbite/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_test_helper.dart';

/// Regression tests for the app-resume update check.
///
/// The widget root registers a [WidgetsBindingObserver] so that returning to
/// the foreground (not just a cold start) re-runs the update check — a user
/// who backgrounds the app before a release is published and returns after
/// it now gets prompted without needing to force-stop the app or wait for
/// the periodic background task. The check is throttled to
/// [UpdateService.resumeCheckMinInterval] (matching the Worker's `/latest`
/// 5-minute edge TTL), which these tests lock in.
void main() {
  setUpAll(() async {
    await setupFirebaseForTest();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Campus Bite',
      packageName: 'com.example.campusbite',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    UpdateService.instance.debugResetForTest();
    UpdateService.debugForceCheckEnabled = true;
    UpdateService.debugLatestFetcher = null;
  });

  tearDown(() {
    UpdateService.instance.debugResetForTest();
    UpdateService.debugForceCheckEnabled = false;
    UpdateService.debugLatestFetcher = null;
  });

  testWidgets('resume after a meaningful background triggers an update check',
      (WidgetTester tester) async {
    var fetches = 0;
    UpdateService.debugLatestFetcher = () async {
      fetches++;
      return null; // network outcome is irrelevant — we assert the check ran
    };

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // Advance the fake clock past the resume throttle so the check is not
    // skipped. `clock.now()` (used by _MyAppState) follows the test clock.
    await tester.pump(UpdateService.resumeCheckMinInterval +
        const Duration(minutes: 1));
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(fetches, 1);
  });

  testWidgets('resume check is throttled — rapid resume does not re-check',
      (WidgetTester tester) async {
    var fetches = 0;
    UpdateService.debugLatestFetcher = () async {
      fetches++;
      return null;
    };

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // A genuine first resume after the cold start.
    await tester.pump(UpdateService.resumeCheckMinInterval +
        const Duration(minutes: 1));
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(fetches, 1);

    // Second resume within the throttle window (e.g. notification shade
    // pull) must not hit the endpoint again.
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(fetches, 1);
  });

  testWidgets('the launch-time resume event does not double-check',
      (WidgetTester tester) async {
    var fetches = 0;
    UpdateService.debugLatestFetcher = () async {
      fetches++;
      return null;
    };

    // Pumping the app fires an initial `resumed` lifecycle event shortly
    // after initState. The cold-start check already ran in main(), so this
    // first resume must be throttled out.
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.pump();

    expect(fetches, 0);
  });
}
