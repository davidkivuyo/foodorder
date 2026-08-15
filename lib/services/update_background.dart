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

import 'dart:ui' show DartPluginRegistrant;

import 'package:workmanager/workmanager.dart';

import 'app_log.dart';
import 'update_platform.dart';
import 'update_service.dart';

/// Unique name of the periodic update-check task.
const String kUpdateCheckTaskName = 'campusbite-update-check';

/// How often the app re-checks while installed (not every launch).
///
/// Every `checkForUpdate()` now revalidates against the endpoint
/// (stale-while-revalidate), so this interval is the heartbeat that keeps
/// long-lived app processes current even when the user never cold-starts the
/// app: a release published at any point is picked up by the next periodic
/// run. The 12h local cache still provides the instant/offline decision path;
/// the Worker's 5-minute edge cache absorbs the extra `/latest` reads.
const Duration kUpdateCheckInterval = Duration(hours: 8);

/// Entry point executed by WorkManager in a background isolate.
///
/// Must be a top-level function annotated for tree-shaking. It performs the
/// same cache-respecting check the foreground does, then exits. Any failure is
/// swallowed so the task always "succeeds" from the OS perspective.
@pragma('vm:entry-point')
void updateBackgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == kUpdateCheckTaskName) {
      try {
        // Plugins (SharedPreferences, package_info_plus) are not auto-
        // registered in the WorkManager background isolate; register them
        // before touching any plugin-backed API.
        DartPluginRegistrant.ensureInitialized();
        AppLog.d('[Update] background isolate plugin registrant initialized');
        await UpdateService.instance.checkForUpdate();
      } on Exception catch (e) {
        AppLog.w('[Update] background check swallowed error: '
            '${e.runtimeType}');
      }
    }
    return true;
  });
}

/// Registers the periodic update-check task (idempotent).
///
/// No-op unless in-app APK updates are supported (Android only) — scheduling a
/// WorkManager task on platforms that can never install an APK is wasted work
/// and may produce startup noise where WorkManager is unsupported.
Future<void> registerPeriodicUpdateCheck() async {
  if (!UpdateService.buildEnabled) return;
  if (!updatePlatform.supported) return;
  try {
    await Workmanager().initialize(updateBackgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      kUpdateCheckTaskName,
      kUpdateCheckTaskName,
      frequency: kUpdateCheckInterval,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } on Exception catch (e) {
    AppLog.w('[Update] could not schedule background check: '
        '${e.runtimeType}');
  }
}
