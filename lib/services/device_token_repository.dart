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

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repository for managing FCM device tokens in the `device_tokens` collection.
///
/// Each device installation gets its own document with an auto-generated
/// Firestore document ID. The document ID is persisted in SharedPreferences
/// so the same installation always finds and updates its own document,
/// even across app restarts and re-logins.
///
/// A genuine per-installation UUID is stored as the `deviceId` field,
/// generated once on first app launch. This allows multiple devices on
/// the same platform (e.g., two Android phones) to remain independent.
///
/// Fields: userId, role, token, platform, deviceId, appVersion, createdAt,
/// updatedAt, lastSeen, active
///
/// Phase 8: Token lifecycle management for FCM push notifications.
class DeviceTokenRepository {
  final FirebaseFirestore _firestore;

  static const String _collection = 'device_tokens';

  // SharedPreferences keys
  static const String _installationIdKey = 'fcm_device_installation_id';
  static const String _legacyDeviceDocIdKey = 'fcm_device_doc_id';

  /// Build a userId-scoped key for the persisted device document ID.
  ///
  /// Each user on the same device gets their own Firestore document,
  /// scoped by userId so that switching accounts does not reuse another
  /// user's token document (which would have an immutable userId field).
  static String _deviceDocIdKeyFor(String userId) =>
      'fcm_device_doc_id_$userId';

  DeviceTokenRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Token Registration ──────────────────────────────────────────────────────

  /// Register (or update) the current device's FCM token.
  ///
  /// On first call, creates a new document via `add()` and persists its
  /// auto-generated document ID in SharedPreferences. Subsequent calls
  /// (including token refresh) update that same document by ID.
  ///
  /// Returns `true` on success, `false` on failure.
  Future<bool> registerToken({
    required String userId,
    required String role,
    required String token,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final platform = _getPlatform();
      const appVersion = '1.0.0';
      final installationId = await _getOrCreateInstallationId(prefs);

      // ── Migration: carry over old global key to user-scoped key ──
      // Before userId-scoped keys, the doc ID was stored under a single
      // global key. If that global value exists and the user-scoped key
      // does not, migrate it so existing installations don't lose their
      // document on the first post-migration login.
      final userKey = _deviceDocIdKeyFor(userId);
      await _migrateLegacyDocId(prefs, userKey);

      // Check if we already have a saved document ID for this user
      final savedDocId = prefs.getString(userKey);

      if (savedDocId != null && savedDocId.isNotEmpty) {
        // Saved doc ID exists — try to update it
        final docRef = _firestore.collection(_collection).doc(savedDocId);
        final docSnapshot = await docRef.get();

        if (docSnapshot.exists) {
          // userId and role are immutable in Firestore rules after creation.
          // They were set correctly when the doc was first created.
          await docRef.update({
            'token': token,
            'platform': platform,
            'appVersion': appVersion,
            'active': true,
            'lastSeen': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return true;
        }
        // Doc was deleted (e.g., by cleanup) — fall through to create a new one
      }

      // No saved doc ID or doc was deleted — create a new document
      // 🔍 DEBUG: Log the full payload that will be sent to Firestore
      final Map<String, dynamic> payload = {
        'userId': userId,
        'role': role,
        'token': token,
        'platform': platform,
        'deviceId': installationId,
        'appVersion': appVersion,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
      };
      debugPrint(
        '[DeviceTokenRepository] Creating device_tokens doc for userId=$userId '
        'role=$role platform=$platform deviceId=$installationId',
      );
      final docRef = await _firestore.collection(_collection).add(payload);

      // Persist the new document ID scoped to this user
      await prefs.setString(userKey, docRef.id);

      return true;
    } catch (e) {
      debugPrint('[DeviceTokenRepository] registerToken error: $e');
      return false;
    }
  }

  /// Deactivate the current device's token (used on logout).
  ///
  /// Looks up the persisted document ID from SharedPreferences and sets
  /// `active = false`. The document is preserved for cleanup functions.
  /// If no saved doc ID exists, this is a no-op.
  Future<bool> deactivateToken({required String userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userKey = _deviceDocIdKeyFor(userId);
      final savedDocId = prefs.getString(userKey);

      if (savedDocId == null || savedDocId.isEmpty) return true;

      final docRef = _firestore.collection(_collection).doc(savedDocId);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        await docRef.update({
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

  /// Get or create a persistent per-installation UUID.
  ///
  /// Generated once on first app launch and stored in SharedPreferences.
  /// Survives app restarts and re-installation (unless app data is cleared).
  Future<String> _getOrCreateInstallationId(
    SharedPreferences prefs,
  ) async {
    final existing = prefs.getString(_installationIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final newId = _generateUuid();
    await prefs.setString(_installationIdKey, newId);
    return newId;
  }

  /// Migrate the legacy global doc ID key to the user-scoped key.
  ///
  /// Before userId-scoped keys, the doc ID was stored under a single
  /// global key `_legacyDeviceDocIdKey`. On first login after migration,
  /// carry that value over to the user-scoped key and clear the legacy key.
  Future<void> _migrateLegacyDocId(
    SharedPreferences prefs,
    String userKey,
  ) async {
    final existingUserValue = prefs.getString(userKey);
    if (existingUserValue != null && existingUserValue.isNotEmpty) {
      return; // Already have a user-scoped value — nothing to migrate.
    }

    final legacyValue = prefs.getString(_legacyDeviceDocIdKey);
    if (legacyValue != null && legacyValue.isNotEmpty) {
      await prefs.setString(userKey, legacyValue);
      await prefs.remove(_legacyDeviceDocIdKey);
      debugPrint(
        '[DeviceTokenRepository] Migrated legacy doc ID to user-scoped key',
      );
    }
  }

  /// Generate a simple UUID v4 string (no external dependencies).
  String _generateUuid() {
    final rng = Random();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));

    // Set version (4) and variant (RFC 4122)
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    return '${_hex(bytes[0])}${_hex(bytes[1])}${_hex(bytes[2])}${_hex(bytes[3])}-'
        '${_hex(bytes[4])}${_hex(bytes[5])}-'
        '${_hex(bytes[6])}${_hex(bytes[7])}-'
        '${_hex(bytes[8])}${_hex(bytes[9])}-'
        '${_hex(bytes[10])}${_hex(bytes[11])}${_hex(bytes[12])}${_hex(bytes[13])}${_hex(bytes[14])}${_hex(bytes[15])}';
  }

  String _hex(int value) => value.toRadixString(16).padLeft(2, '0');

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
}
