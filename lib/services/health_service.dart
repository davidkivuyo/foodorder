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

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'connectivity_service.dart';
import 'auth_service.dart';
import 'error_service.dart';
import 'fcm_service.dart';
import 'logger_service.dart';
import 'update_service.dart';

/// Health of a single monitored component (Phase 17 — Part 13).
enum ComponentHealth { healthy, degraded, offline, unknown }

/// Overall application health.
enum AppHealth { healthy, degraded, offline, unknown }

/// Immutable snapshot of every monitored dependency.
class HealthSnapshot {
  const HealthSnapshot({
    required this.firestore,
    required this.auth,
    required this.functions,
    required this.cloudinary,
    required this.notifications,
    required this.update,
    required this.overall,
    required this.checkedAt,
  });

  final ComponentHealth firestore;
  final ComponentHealth auth;

  /// The customer app never calls Cloud Functions directly, so this is
  /// always [ComponentHealth.unknown].
  final ComponentHealth functions;
  final ComponentHealth cloudinary;
  final ComponentHealth notifications;
  final ComponentHealth update;
  final AppHealth overall;
  final DateTime checkedAt;
}

/// Application health checks (Phase 17 — Part 13).
///
/// Lightweight, on-demand probes only — this service never polls servers or
/// writes monitoring data to Firestore. [checkHealth] is called when the
/// diagnostics screen opens; connectivity changes are reflected through
/// [ConnectivityService].
class HealthService {
  HealthService._();

  static final HealthService instance = HealthService._();

  bool _firebaseReady = false;

  HealthSnapshot? lastSnapshot;

  /// Marks that Firebase initialized successfully at startup.
  void markFirebaseReady() => _firebaseReady = true;

  /// Runs all component probes and computes the overall status.
  Future<HealthSnapshot> checkHealth() async {
    final online = ConnectivityService().isOnline;
    final firestore = await _checkFirestore();
    final auth = _checkAuth();
    final cloudinary = _checkCloudinary();
    final notifications = _checkNotifications();
    final update = _checkUpdate();

    final overall = computeOverall(
      online: online,
      firestore: firestore,
      auth: auth,
      cloudinary: cloudinary,
      notifications: notifications,
      update: update,
    );

    final snapshot = HealthSnapshot(
      firestore: firestore,
      auth: auth,
      functions: ComponentHealth.unknown,
      cloudinary: cloudinary,
      notifications: notifications,
      update: update,
      overall: overall,
      checkedAt: DateTime.now(),
    );
    lastSnapshot = snapshot;
    return snapshot;
  }

  /// One lightweight on-demand read; permission-denied still proves the
  /// service is reachable.
  Future<ComponentHealth> _checkFirestore() async {
    if (!_firebaseReady) return ComponentHealth.unknown;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('food_items')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));
      if (snapshot.metadata.isFromCache) {
        return ComponentHealth.degraded;
      }
      return ComponentHealth.healthy;
    } on TimeoutException {
      return ComponentHealth.degraded;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return ComponentHealth.healthy;
      return ComponentHealth.degraded;
    } catch (e) {
      LoggerService.instance
          .debug('Firestore health probe failed (${e.runtimeType})');
      return ComponentHealth.offline;
    }
  }

  /// Reports Auth health from the outcome of the last network-backed Auth
  /// operation rather than treating local initialization as availability.
  /// `FirebaseAuth.instance.app` is only a local object access and tells
  /// nothing about backend reachability, so it is no longer used. Without a
  /// recent success the state is [ComponentHealth.unknown].
  ComponentHealth _checkAuth() {
    if (!_firebaseReady) return ComponentHealth.unknown;
    final lastSuccess = AuthService.lastSuccessAt;
    final lastFailure = AuthService.lastFailureAt;
    if (lastSuccess == null) return ComponentHealth.unknown;
    if (DateTime.now().difference(lastSuccess) > _authFreshness) {
      return ComponentHealth.unknown;
    }
    if (lastFailure == null) return ComponentHealth.healthy;
    final lastFailureRecency = DateTime.now().difference(lastFailure);
    if (lastFailure.isAfter(lastSuccess) && lastFailureRecency <= _authFreshness) {
      return ComponentHealth.offline;
    }
    return ComponentHealth.healthy;
  }

  static const Duration _authFreshness = Duration(minutes: 30);
  static const Duration _cloudinaryFreshness = Duration(minutes: 30);

  ComponentHealth _checkCloudinary() {
    final mon = ImageMonitor.instance;
    final lastFailure = mon.lastFailureAt;
    // A stale failure no longer reflects current availability, so the state
    // falls back to unknown once the failure is older than the window.
    final freshFailure =
        lastFailure != null &&
        DateTime.now().difference(lastFailure) <= _cloudinaryFreshness;
    if (freshFailure &&
        (mon.lastSuccessAt == null ||
            lastFailure.isAfter(mon.lastSuccessAt!))) {
      return ComponentHealth.degraded;
    }
    if (mon.lastSuccessAt != null) return ComponentHealth.healthy;
    return ComponentHealth.unknown;
  }

  ComponentHealth _checkNotifications() {
    return FcmService.isActive ? ComponentHealth.healthy : ComponentHealth.unknown;
  }

  ComponentHealth _checkUpdate() {
    switch (UpdateService.instance.state) {
      case UpdateState.current:
      case UpdateState.updateAvailable:
      case UpdateState.updateRequired:
      case UpdateState.installed:
        return ComponentHealth.healthy;
      case UpdateState.failed:
        return ComponentHealth.degraded;
      default:
        return ComponentHealth.unknown;
    }
  }

  /// Pure overall-status computation, exposed for tests.
  @visibleForTesting
  static AppHealth computeOverall({
    required bool online,
    required ComponentHealth firestore,
    required ComponentHealth auth,
    required ComponentHealth cloudinary,
    required ComponentHealth notifications,
    required ComponentHealth update,
  }) {
    if (!online) return AppHealth.offline;
    if (firestore == ComponentHealth.offline ||
        auth == ComponentHealth.offline) {
      return AppHealth.offline;
    }
    final components = <ComponentHealth>[
      firestore,
      auth,
      cloudinary,
      notifications,
      update,
    ];
    if (components.contains(ComponentHealth.offline) ||
        components.contains(ComponentHealth.degraded)) {
      return AppHealth.degraded;
    }
    if (firestore == ComponentHealth.healthy &&
        auth == ComponentHealth.healthy) {
      return AppHealth.healthy;
    }
    if (components.every((c) => c == ComponentHealth.unknown)) {
      return AppHealth.unknown;
    }
    return AppHealth.degraded;
  }
}
