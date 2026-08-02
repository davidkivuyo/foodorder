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
import 'update_blocking_screen.dart';
import 'update_prompt_dialog.dart';
import 'update_ui_helpers.dart';

/// Wraps the whole app and renders the update UI on top of it.
///
/// - Mandatory updates: a full-screen blocking overlay with no way out.
/// - Optional updates: a dismissible prompt; once the user opts in, a
///   dismissible progress overlay tracks the download.
///
/// Placement: use as `MaterialApp.builder` so it sits above the navigator.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  final UpdateService _service = UpdateService.instance;

  /// Whether the user opted into an optional update's download. Used to decide
  /// whether the progress overlay is dismissible.
  bool _optionalFlowActive = false;

  /// Tracks a mandatory update's download flow. Started when an
  /// `updateRequired` state begins downloading and kept active through the
  /// whole forced flow (downloading → paused → verifying → readyToInstall →
  /// installPermissionRequired → installing) so [UpdateBlockingScreen] stays
  /// visible and non-dismissible until the service reaches `installed` or
  /// `current`.
  bool _mandatoryFlowActive = false;

  /// Whether the user dismissed the persistent ready-to-install indicator.
  /// Reset whenever the service leaves [UpdateState.readyToInstall] so the
  /// indicator reappears if a download completes later.
  bool _readyToInstallDismissed = false;

  UpdateState _previousState = UpdateState.idle;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    final state = _service.state;

    // A mandatory update starts its download flow when an update-required
    // state transitions into downloading.
    if (_previousState == UpdateState.updateRequired &&
        state == UpdateState.downloading) {
      _mandatoryFlowActive = true;
    }

    // A user-triggered download from the optional prompt starts this flag.
    if (_previousState == UpdateState.updateAvailable &&
        state == UpdateState.downloading) {
      _optionalFlowActive = true;
    }

    // Reset the optional-download flag only once the flow truly ends
    // (`current`). The `installed` state must still reach _Body so the
    // completion message can render inside the optional sheet.
    if (state == UpdateState.current) {
      _optionalFlowActive = false;
    }

    // The mandatory flow only ends when the update is installed or the app is
    // reported current; before that the blocking screen stays up even during
    // the installation states.
    if (state == UpdateState.installed ||
        state == UpdateState.current) {
      _mandatoryFlowActive = false;
    }

    // A dismiss of the ready-to-install indicator only applies to that exact
    // readyToInstall stay; if the flow leaves the state (e.g. retry), show it
    // again next time a download completes.
    if (state != UpdateState.readyToInstall) {
      _readyToInstallDismissed = false;
    }

    _previousState = state;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _service.state;

    if (state == UpdateState.updateRequired || _mandatoryFlowActive) {
      // Mandatory updates stay blocking for the entire lifecycle — download,
      // pause, verify, ready-to-install, permission, install, completion and
      // failure all render inside UpdateBlockingScreen so the app cannot be
      // used until the update is done.
      return UpdateBlockingScreen(service: _service);
    }

    if (state == UpdateState.updateAvailable && !_service.dismissed) {
      return PopScope(
        // Block system back — the optional prompt cannot be popped past the
        // underlying navigator; dismiss it with the "Later" action instead.
        canPop: false,
        child: Stack(
          children: [
            widget.child,
            const ModalBarrier(dismissible: false, color: Colors.black54),
            UpdatePromptDialog(service: _service),
          ],
        ),
      );
    }

    // Persistent ready-to-install indicator. A download that completed while
    // the optional sheet was dismissed (or after it was closed) leaves a
    // verified installer on disk; always surface an install affordance for it,
    // independently of the optional-flow flag. The install-tail states are
    // only reachable from this sheet, so they keep it visible too.
    final hasInstaller =
        state == UpdateState.readyToInstall ||
        state == UpdateState.installPermissionRequired ||
        state == UpdateState.installing ||
        state == UpdateState.installed;
    if (hasInstaller && !_readyToInstallDismissed) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          setState(() => _readyToInstallDismissed = true);
        },
        child: Stack(
          children: [
            widget.child,
            const ModalBarrier(dismissible: false, color: Colors.black54),
            _OptionalProgressSheet(
              service: _service,
              onClose: () {
                setState(() => _readyToInstallDismissed = true);
              },
            ),
          ],
        ),
      );
    }

    // Optional flow mid-download: dismissible progress overlay.
    if (_optionalFlowActive &&
        state != UpdateState.current &&
        state != UpdateState.updateAvailable) {
      return PopScope(
        // Route system back through the sheet's own close handler so
        // _service.dismiss() and _optionalFlowActive stay in sync.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _service.dismiss();
          setState(() => _optionalFlowActive = false);
        },
        child: Stack(
          children: [
            widget.child,
            const ModalBarrier(dismissible: false, color: Colors.black54),
            _OptionalProgressSheet(
              service: _service,
              onClose: () {
                _service.dismiss();
                setState(() => _optionalFlowActive = false);
              },
            ),
          ],
        ),
      );
    }

    return widget.child;
  }
}

class _OptionalProgressSheet extends StatelessWidget {
  const _OptionalProgressSheet({required this.service, required this.onClose});

  final UpdateService service;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel',
                ),
              ),
              Text(
                'Updating Campus Bite',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _Body(service: service),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.service});

  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    switch (service.state) {
      case UpdateState.downloading:
        final progress = service.progress.clamp(0.0, 1.0);
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 13)),
                Text('ETA ${formatEta(service.eta)}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: service.pause, child: const Text('Pause')),
          ],
        );
      case UpdateState.paused:
        return TextButton(
          onPressed: service.startDownload,
          child: const Text('Resume download'),
        );
      case UpdateState.verifying:
        return const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Verifying update…'),
          ],
        );
      case UpdateState.readyToInstall:
        return FilledButton.icon(
          onPressed: service.install,
          icon: const Icon(Icons.system_update_alt),
          label: const Text('Install update'),
        );
      case UpdateState.installPermissionRequired:
        return Column(
          children: [
            const Text(
              'To install the update, allow the app to install apps from '
              'unknown sources.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: service.openInstallSettings,
              child: const Text('Open settings'),
            ),
            TextButton(
              onPressed: service.refreshInstallPermission,
              child: const Text('I enabled it'),
            ),
          ],
        );
      case UpdateState.installing:
        return const Text('Installing update…', textAlign: TextAlign.center);
      case UpdateState.installed:
        return const Text('Update completed.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold));
      case UpdateState.failed:
        return Column(
          children: [
            Text(service.errorMessage ?? 'Something went wrong.',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            if (service.errorRetryable)
              FilledButton.icon(
                onPressed: service.retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
