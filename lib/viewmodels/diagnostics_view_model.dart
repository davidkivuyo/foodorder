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

import '../services/diagnostics_service.dart';

/// ViewModel for [DiagnosticsScreen] and [DiagnosticsEntryTile] (Phase 17 —
/// Part 14).
///
/// Owns all diagnostics business logic so the widgets stay UI-only:
/// - resolving access (debug builds always; otherwise only administrator
///   accounts) via the role lookup
/// - collecting the [DiagnosticsSnapshot]
/// - exposing an access-denied/loading/error state surface for the view
///
/// The widgets only observe this ViewModel and trigger its actions.
class DiagnosticsViewModel extends ChangeNotifier {
  DiagnosticsViewModel({DiagnosticsService? diagnosticsService})
      : _service = diagnosticsService ?? DiagnosticsService.instance;

  final DiagnosticsService _service;

  /// Whether diagnostics may be rendered:
  /// `true` — allowed (debug build, or role resolved to admin);
  /// `false` — denied (release and non-admin, or role lookup failed);
  /// `null` — still resolving.
  bool? _allowed;

  DiagnosticsSnapshot? _snapshot;
  bool _hasError = false;
  bool _disposed = false;

  bool? get allowed => _allowed;
  DiagnosticsSnapshot? get snapshot => _snapshot;
  bool get hasError => _hasError;

  /// Stops notifying listeners once this ViewModel has been disposed so that
  /// pending async operations can settle without touching a dead notifier.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Resolves visibility. Debug builds are always allowed; otherwise access
  /// depends on the account role. On success (and when allowed) the snapshot
  /// is loaded. When the role lookup fails the screen is denied rather than
  /// letting the exception escape an async callback.
  Future<void> resolveAccess() async {
    if (_allowed != null) return;
    if (kDebugMode) {
      _allowed = true;
      _safeNotify();
      await load();
      return;
    }
    try {
      final role = await _service.fetchUserRole();
      _allowed = shouldShowDiagnostics(debugMode: false, role: role);
      _safeNotify();
      if (_allowed == true) await load();
    } catch (_) {
      // Role resolution failed — deny access.
      if (_disposed) return;
      _allowed = false;
      _safeNotify();
    }
  }

  /// Collects the diagnostics snapshot, or surfaces an error state.
  Future<void> load() async {
    _setHasError(false);
    try {
      final snapshot = await _service.collect();
      if (_disposed) return;
      _snapshot = snapshot;
      _safeNotify();
    } on Object catch (_) {
      // Both Exceptions and Errors (e.g. platform-channel failures) clear the
      // loading state and surface the retry UI.
      if (_disposed) return;
      _hasError = true;
      _safeNotify();
    }
  }

  /// Clears the loaded snapshot and recollects it.
  Future<void> refresh() async {
    _snapshot = null;
    _safeNotify();
    await load();
  }

  void _setHasError(bool value) {
    if (_disposed || _hasError == value) return;
    _hasError = value;
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Shared visibility decision, kept out of the widgets so the ViewModel can
/// reuse it without importing view files.
bool shouldShowDiagnostics({required bool debugMode, required String role}) =>
    debugMode || role == 'admin';