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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/food_data.dart';
import 'analytics_service.dart';
import 'crash_reporting_service.dart';
import 'fcm_service.dart';
import 'health_service.dart';
import 'performance_service.dart';
import 'platform_info.dart' show platformName, sdkVersion;

/// Firebase package versions, mirroring pubspec.yaml (diagnostics only).
const Map<String, String> kFirebaseVersions = {
  'firebase_core': '4.11.0',
  'firebase_auth': '6.5.4',
  'cloud_firestore': '6.6.0',
  'firebase_app_check': '0.4.5',
  'firebase_messaging': '16.4.1',
  'firebase_crashlytics': '5.2.4',
  'firebase_analytics': '12.4.3',
  'firebase_performance': '0.11.4',
};

/// Anonymous snapshot of application diagnostics (Phase 17 — Part 14).
///
/// Contains technical state only — no emails, UIDs, tokens or personal
/// content — so it is safe to render on the hidden diagnostics screen.
class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.appVersion,
    required this.buildNumber,
    required this.sdkVersion,
    required this.platform,
    required this.firebaseVersions,
    required this.persistenceEnabled,
    required this.userRole,
    required this.notificationActive,
    required this.analyticsAvailable,
    required this.crashlyticsAvailable,
    required this.performanceAvailable,
    required this.lastSyncAt,
    required this.health,
    required this.checkedAt,
  });

  final String appVersion;
  final String buildNumber;
  final String sdkVersion;
  final String platform;
  final Map<String, String> firebaseVersions;

  /// Whether Firestore offline persistence is explicitly enabled.
  ///
  /// `null` means the setting was never configured (or could not be read) —
  /// which is NOT the same as disabled: mobile Firestore enables persistence
  /// by default, while web ignores this setting entirely.
  final bool? persistenceEnabled;
  final String userRole;
  final bool notificationActive;
  final bool analyticsAvailable;
  final bool crashlyticsAvailable;
  final bool performanceAvailable;
  final DateTime? lastSyncAt;
  final HealthSnapshot health;
  final DateTime checkedAt;
}

/// Aggregates technical diagnostics for the hidden developer screen
/// (Phase 17 — Part 14).
class DiagnosticsService {
  DiagnosticsService._();

  static final DiagnosticsService instance = DiagnosticsService._();

  String? _cachedRole;
  String? _cachedRoleUserId;

  /// Fetches the current user's role from Firestore, cached for the session.
  /// Never exposed to analytics/crash reports — role only, never the UID.
  ///
  /// The cache is per-user: a cached role is only reused when the requesting
  /// UID matches the one it was fetched for, so a role belonging to a
  /// previous account is never served to a different user.
  Future<String> fetchUserRole([String? uid]) async {
    final userId = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return 'guest';
    if (_cachedRoleUserId == userId && _cachedRole != null) {
      return _cachedRole!;
    }
    String role = 'student';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 5));
      role = doc.data()?['role'] as String? ?? 'student';
    } catch (_) {
      // Degrade gracefully to the default role.
    }
    _cachedRole = role;
    _cachedRoleUserId = userId;
    return role;
  }

  /// Guards the platform-channel lookup so diagnostics collection and the
  /// diagnostics screen keep working when [PackageInfo.fromPlatform] throws
  /// (e.g. unsupported platform or test environment). Placeholder values are
  /// used in that case; the caller never sees an exception.
  Future<PackageInfo> _resolvePackageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return PackageInfo(
        appName: 'CampusBite',
        packageName: 'unknown',
        version: 'unknown',
        buildNumber: 'unknown',
      );
    }
  }

  /// Collects the full diagnostics snapshot.
  Future<DiagnosticsSnapshot> collect() async {
    final pkg = await _resolvePackageInfo();
    final role = await fetchUserRole();
    final health = await HealthService.instance.checkHealth();
    return DiagnosticsSnapshot(
      appVersion: pkg.version,
      buildNumber: pkg.buildNumber,
      sdkVersion: sdkVersion,
      platform: platformName,
      firebaseVersions: kFirebaseVersions,
      persistenceEnabled: _persistenceEnabled(),
      userRole: role,
      notificationActive: FcmService.isActive,
      analyticsAvailable: AnalyticsService.instance.isAvailable,
      crashlyticsAvailable: CrashReportingService.instance.isAvailable,
      performanceAvailable: PerformanceService.instance.isAvailable,
      lastSyncAt: FoodData.lastSuccessfulSyncAt,
      health: health,
      checkedAt: DateTime.now(),
    );
  }

  /// Reads the Firestore persistence setting without inventing a value.
  ///
  /// A null `Settings.persistenceEnabled` (or an unreadable settings lookup)
  /// is reported as null — "not configured / unknown" — never as `false`,
  /// because mobile Firestore enables persistence by default while web does
  /// not use this setting at all.
  bool? _persistenceEnabled() {
    try {
      return FirebaseFirestore.instance.settings.persistenceEnabled;
    } on Exception catch (_) {
      return null;
    }
  }
}
