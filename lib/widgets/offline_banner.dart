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
import '../viewmodels/offline_banner_view_model.dart';

/// Banner widget that displays network status and sync recovery progress.
///
/// Pure view: all connectivity/sync business logic lives in
/// [OfflineBannerViewModel]. When no [viewModel] is supplied, the widget
/// creates and owns its own instance.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, this.viewModel});

  /// Optional injected ViewModel (used by tests). When null, the widget
  /// creates and disposes its own instance.
  final OfflineBannerViewModel? viewModel;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  late OfflineBannerViewModel _viewModel;
  late final bool _ownsViewModel;

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _viewModel = widget.viewModel ?? OfflineBannerViewModel();
  }

  @override
  void dispose() {
    if (_ownsViewModel) {
      _viewModel.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final vm = _viewModel;
        if (vm.isHidden) {
          return const SizedBox.shrink();
        }

        Color bgColor;
        Widget icon;
        String message;

        if (!vm.isOnline) {
          bgColor = Colors.amber.shade900;
          icon = const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16);
          message = vm.pendingCount > 0
              ? 'Offline Mode • ${vm.pendingCount} queued action(s)'
              : 'Offline Mode • Changes will sync when online';
        } else if (vm.isSyncing) {
          bgColor = Colors.blue.shade800;
          icon = const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          );
          message = 'Syncing queued actions...';
        } else if (vm.showBackOnline) {
          bgColor = Colors.green.shade800;
          icon = const Icon(
            Icons.check_circle_outline,
            color: Colors.white,
            size: 16,
          );
          message = 'Back Online • Connectivity restored';
        } else if (vm.pendingCount > 0) {
          bgColor = Colors.indigo.shade800;
          icon = const Icon(Icons.sync_rounded, color: Colors.white, size: 16);
          message = '${vm.pendingCount} pending sync action(s)';
        } else {
          return const SizedBox.shrink();
        }

        return AnimatedPadding(
          duration: const Duration(milliseconds: 300),
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            color: bgColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SafeArea(
              bottom: true,
              top: false,
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (vm.canSyncNow)
                    GestureDetector(
                      onTap: () => vm.syncNow(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Sync Now',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
