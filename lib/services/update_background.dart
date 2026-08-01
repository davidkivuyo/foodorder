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
import 'package:workmanager/workmanager.dart';

import 'app_log.dart';
import 'update_service.dart';

/// Unique name of the periodic update-check task.
const String kUpdateCheckTaskName = 'campusbite-update-check';

/// How often the app re-checks while installed (not every launch).
///
/// Deliberately shorter than [UpdateService.localCacheTtl] (12h): periodic
/// execution can jitter around the scheduled time, and with equal intervals a
/// run landing just before the cached metadata expires would force a network
/// call at the next boundary. Being below the cache TTL leaves a safety
/// margin while `checkForUpdate`'s cache gate still caps actual network calls
/// at one per cache-validity window.
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
        await UpdateService.instance.checkForUpdate();
      } catch (e) {
        AppLog.w('[Update] background check swallowed error: '
            '${e.runtimeType}');
      }
    }
    return true;
  });
}

/// Registers the periodic update-check task (idempotent). No-op on web.
Future<void> registerPeriodicUpdateCheck() async {
  if (kIsWeb) return;
  try {
    await Workmanager().initialize(updateBackgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      kUpdateCheckTaskName,
      kUpdateCheckTaskName,
      frequency: kUpdateCheckInterval,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (e) {
    AppLog.w('[Update] could not schedule background check: '
        '${e.runtimeType}');
  }
}
