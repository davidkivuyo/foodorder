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

import '../services/diagnostics_service.dart';
import '../services/health_service.dart';
import '../viewmodels/diagnostics_view_model.dart';

/// Hidden developer diagnostics screen (Phase 17 — Part 14).
///
/// Visible only in debug builds or for administrator accounts. Renders
/// technical state only — no emails, UIDs, tokens or personal content.
///
/// This widget is a pure View: it renders state from
/// [DiagnosticsViewModel] and triggers its actions. All business logic
/// (access resolution, role lookup, snapshot collection) lives in the
/// ViewModel.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late final DiagnosticsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DiagnosticsViewModel();
    _viewModel.addListener(_onViewModelChanged);
    _viewModel.resolveAccess();
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_viewModel.allowed != true) {
      // Access denied (or still being checked) — render nothing rather than
      // leaking diagnostics data.
      return const Scaffold(body: SizedBox.shrink());
    }
    final snapshot = _viewModel.snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _viewModel.snapshot == null ? null : _viewModel.refresh,
          ),
        ],
      ),
      body: _buildBody(snapshot),
    );
  }

  Widget _buildBody(DiagnosticsSnapshot? snapshot) {
    if (_viewModel.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load diagnostics.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _viewModel.load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Application',
          children: [
            _Row(label: 'Version', value: snapshot.appVersion),
            _Row(label: 'Build', value: snapshot.buildNumber),
            _Row(label: 'SDK version', value: snapshot.sdkVersion),
            _Row(label: 'Platform', value: snapshot.platform),
          ],
        ),
        _Section(
          title: 'Firebase',
          children: [
            for (final entry in snapshot.firebaseVersions.entries)
              _Row(label: entry.key, value: entry.value),
          ],
        ),
        _Section(
          title: 'Storage',
          children: [
            _Row(
              label: 'Offline persistence',
              // Tri-state: null means "not configured / unknown", which is
              // not the same as disabled (mobile Firestore persists by
              // default; web ignores the setting).
              value: switch (snapshot.persistenceEnabled) {
                true => 'enabled',
                false => 'disabled',
                null => 'not configured',
              },
            ),
            _Row(
              label: 'Last sync',
              value: _formatTime(snapshot.lastSyncAt),
            ),
          ],
        ),
        _Section(
          title: 'Monitoring',
          children: [
            _Row(
              label: 'Role',
              value: snapshot.userRole,
            ),
            _Row(
              label: 'Notifications',
              value: snapshot.notificationActive ? 'active' : 'inactive',
            ),
            _Row(
              label: 'Analytics',
              value: snapshot.analyticsAvailable ? 'enabled' : 'unavailable',
            ),
            _Row(
              label: 'Crashlytics',
              value:
                  snapshot.crashlyticsAvailable ? 'enabled' : 'unavailable',
            ),
            _Row(
              label: 'Performance',
              value:
                  snapshot.performanceAvailable ? 'enabled' : 'unavailable',
            ),
          ],
        ),
        _Section(
          title: 'Service health',
          children: [
            _Row(label: 'Overall', value: _healthName(snapshot.health.overall)),
            _Row(
              label: 'Firestore',
              value: _componentName(snapshot.health.firestore),
            ),
            _Row(label: 'Auth', value: _componentName(snapshot.health.auth)),
            _Row(
              label: 'Cloudinary',
              value: _componentName(snapshot.health.cloudinary),
            ),
            _Row(
              label: 'Notifications',
              value: _componentName(snapshot.health.notifications),
            ),
            _Row(
              label: 'Update service',
              value: _componentName(snapshot.health.update),
            ),
            _Row(
              label: 'Cloud Functions',
              value: _componentName(snapshot.health.functions),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Diagnostics contain technical data only. No personal information '
          'is collected or displayed.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return 'never';
    final local = time.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  String _componentName(ComponentHealth health) => health.name;
  String _healthName(AppHealth health) => health.name;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Entry tile shown only in debug builds or for administrator accounts
/// (Phase 17 — Part 14).
class DiagnosticsEntryTile extends StatefulWidget {
  const DiagnosticsEntryTile({super.key});

  /// Visibility decision, shared with the router guard: the diagnostics
  /// entry (and route) are shown in debug builds or when [role] is the
  /// administrator role.
  static bool shouldShowDiagnostics({
    required bool debugMode,
    required String role,
  }) =>
      debugMode || role == 'admin';

  @override
  State<DiagnosticsEntryTile> createState() => _DiagnosticsEntryTileState();
}

class _DiagnosticsEntryTileState extends State<DiagnosticsEntryTile> {
  late final DiagnosticsViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DiagnosticsViewModel();
    _viewModel.addListener(_onViewModelChanged);
    _viewModel.resolveAccess();
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_viewModel.allowed != true) return const SizedBox.shrink();
    return Column(
      children: [
        const Divider(height: 1),
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: Colors.blueGrey.shade50,
            child: const Icon(Icons.monitor_heart_outlined,
                color: Colors.blueGrey, size: 22),
          ),
          title: const Text(
            'Developer Diagnostics',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text('App health, versions and monitoring status'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
          ),
        ),
      ],
    );
  }
}
