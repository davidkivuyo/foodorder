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

import 'package:flutter/material.dart';

import '../services/update_service.dart';
import 'update_ui_helpers.dart';

/// Dismissible prompt shown when an optional update is available.
///
/// Rendered as a raw [AlertDialog] inside [UpdateGate]'s Stack (no route), so
/// it supplies its own Material surface. Dismiss via [service.dismiss].
///
/// Because it is not a real route, it must explicitly trap keyboard focus and
/// accessibility scope so Tab/TalkBack traversal cannot reach the app behind
/// the [ModalBarrier].
class UpdatePromptDialog extends StatelessWidget {
  const UpdatePromptDialog({super.key, required this.service});

  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: FocusScope(
        autofocus: true,
        child: Center(
          child: AlertDialog(
            title: const Text(UpdateCopy.title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (service.info != null)
                    ReleaseNotesView(notes: service.info!.releaseNotes),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: service.dismiss,
                child: const Text(UpdateCopy.later),
              ),
              FilledButton(
                onPressed: () {
                  // Starting the download moves the service to `downloading`,
                  // which removes this dialog from the gate's Stack.
                  service.startDownload();
                },
                child: const Text(UpdateCopy.updateNow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
