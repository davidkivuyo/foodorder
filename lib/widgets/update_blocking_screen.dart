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

/// Full-screen widget shown when an update is mandatory.
///
/// No dismiss, no navigation, no "Later" — the app cannot be used until the
/// update is installed. Handles every stage of the flow (idle/required →
/// download → verify → install → completed / failure).
class UpdateBlockingScreen extends StatelessWidget {
  const UpdateBlockingScreen({super.key, required this.service});

  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block system back — mandatory updates cannot be dismissed.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: AnimatedBuilder(
            animation: service,
            builder: (context, _) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.system_update_alt_rounded,
                          size: 72,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          UpdateCopy.title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'This update is required to keep using the app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 24),
                        if (service.info != null)
                          ReleaseNotesView(notes: service.info!.releaseNotes),
                        const SizedBox(height: 24),
                        _buildBody(context),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (service.state) {
      case UpdateState.downloading:
        return _DownloadProgressView(service: service);
      case UpdateState.paused:
        return _PausedView(service: service);
      case UpdateState.verifying:
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Verifying update…'),
            ],
          ),
        );
      case UpdateState.readyToInstall:
        return _ReadyToInstallView(service: service);
      case UpdateState.installPermissionRequired:
        return _PermissionRequiredView(service: service);
      case UpdateState.installing:
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(UpdateCopy.installing),
            ],
          ),
        );
      case UpdateState.installed:
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Column(
            children: [
              Icon(Icons.check_circle, size: 48, color: Colors.green),
              SizedBox(height: 16),
              Text(UpdateCopy.completed,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      case UpdateState.failed:
        return _ErrorView(service: service);
      default:
        return FilledButton.icon(
          onPressed: service.startDownload,
          icon: const Icon(Icons.download),
          label: const Text(UpdateCopy.download),
        );
    }
  }
}

class _DownloadProgressView extends StatelessWidget {
  const _DownloadProgressView({required this.service});

  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    final progress = service.progress.clamp(0.0, 1.0);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              service.totalBytes > 0
                  ? '${formatBytes(service.receivedBytes)} / '
                      '${formatBytes(service.totalBytes)}'
                  : formatBytes(service.receivedBytes),
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(UpdateCopy.downloading,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            Text(
              'ETA ${formatEta(service.eta)}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: service.pause,
          child: const Text(UpdateCopy.pause),
        ),
      ],
    );
  }
}

class _PausedView extends StatelessWidget {
  const _PausedView({required this.service});

  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Download paused',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: service.startDownload,
          icon: const Icon(Icons.play_arrow),
          label: const Text(UpdateCopy.resume),
        ),
      ],
    );
  }
}

class _ReadyToInstallView extends StatelessWidget {
  const _ReadyToInstallView({required this.service});

  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('The update is ready to install.'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: service.install,
          icon: const Icon(Icons.system_update_alt),
          label: const Text(UpdateCopy.install),
        ),
      ],
    );
  }
}

class _PermissionRequiredView extends StatelessWidget {
  const _PermissionRequiredView({required this.service});

  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'To install the update, allow the app to install apps from '
          'unknown sources.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: service.openInstallSettings,
          icon: const Icon(Icons.settings),
          label: const Text(UpdateCopy.openSettings),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: service.refreshInstallPermission,
          child: const Text('I enabled it'),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.service});

  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
        const SizedBox(height: 12),
        Text(
          service.errorMessage ?? 'Something went wrong.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 12),
        if (service.errorRetryable)
          FilledButton.icon(
            onPressed: service.retry,
            icon: const Icon(Icons.refresh),
            label: const Text(UpdateCopy.retry),
          ),
      ],
    );
  }
}
