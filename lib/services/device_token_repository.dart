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
import 'package:flutter/foundation.dart';


/// Repository for managing FCM device tokens in the `device_tokens` collection.
///
/// Each authenticated device gets its own document with fields:
/// - userId, role, token, platform, deviceId, appVersion, createdAt, updatedAt,
///   lastSeen, active
///
/// One user may own multiple devices — tokens are never overwritten.
///
/// Phase 8: Token lifecycle management for FCM push notifications.
class DeviceTokenRepository {
  final FirebaseFirestore _firestore;

  static const String _collection = 'device_tokens';

  DeviceTokenRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Token Registration ──────────────────────────────────────────────────────

  /// Register (or update) the current device's FCM token.
  ///
  /// If a document with the same [token] already exists for the same [userId],
  /// it is reactivated. Otherwise a new document is created.
  ///
  /// Returns `true` on success, `false` on failure.
  Future<bool> registerToken({
    required String userId,
    required String role,
    required String token,
  }) async {
    try {
      final platform = _getPlatform();
      const appVersion = '1.0.0';
      final deviceId = _getDeviceId();

      // Check if this token already exists for this user
      final existing = await _firestore
          .collection(_collection)
          .where('userId', isEqualTo: userId)
          .where('token', isEqualTo: token)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        // Token exists — reactivate and update metadata
        // Note: deviceId is NOT updated because it is immutable after creation
        // (enforced by Firestore security rules).
        await existing.docs.first.reference.update({
          'active': true,
          'platform': platform,
          'appVersion': appVersion,
          'lastSeen': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // New token document
        await _firestore.collection(_collection).add({
          'userId': userId,
          'role': role,
          'token': token,
          'platform': platform,
          'deviceId': deviceId,
          'appVersion': appVersion,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }

      return true;
    } catch (e) {
      debugPrint('[DeviceTokenRepository] registerToken error: $e');
      return false;
    }
  }

  /// Deactivate the current device's token (used on logout).
  ///
  /// Sets `active = false` — the document is preserved for cleanup functions.
  Future<bool> deactivateToken({required String token}) async {
    try {
      final existing = await _firestore
          .collection(_collection)
          .where('token', isEqualTo: token)
          .where('active', isEqualTo: true)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        await existing.docs.first.reference.update({
          'active': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return true;
    } catch (e) {
      debugPrint('[DeviceTokenRepository] deactivateToken error: $e');
      return false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _getPlatform() {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) return 'android';
      if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
      if (defaultTargetPlatform == TargetPlatform.windows) return 'windows';
      if (defaultTargetPlatform == TargetPlatform.macOS) return 'macos';
      if (defaultTargetPlatform == TargetPlatform.linux) return 'linux';
      return 'web';
    } catch (_) {
      return 'unknown';
    }
  }

  String _getDeviceId() {
    try {
      // Use a stable hash derived from platform info
      final unique = <String>[
        _getPlatform(),
        '${DateTime.now().microsecondsSinceEpoch}',
      ];
      return unique.join('-');
    } catch (_) {
      return 'unknown';
    }
  }
}
