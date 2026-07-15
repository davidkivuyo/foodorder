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
import '../models/strike_model.dart';
import '../models/audit_log.dart';

/// Manages strike operations for student accounts.
///
/// Business logic must live here — never inside Widgets.
/// All strike actions are logged to the `audit_logs` collection.
///
/// Phase 6: Only store `strikeCount` and `accountStatus` in Firestore.
/// `strikePercentage` is derived in the app as `strikeCount * 50`.
/// Read `strikePercentage` only for backward compat with legacy documents.
class StrikeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Stream Helpers ──────────────────────────────────────────────────────────

  /// Returns a live stream of the user document for the given [userId].
  /// Used by the StrikeStatusCard for automatic updates.
  Stream<DocumentSnapshot<Map<String, dynamic>>> strikeStream(
    String userId,
  ) {
    return _firestore.collection('users').doc(userId).snapshots();
  }

  /// Helper to extract strike data from a user document snapshot.
  ///
  /// Phase 6: Derive percentage from `strikeCount * 50`.
  /// Fall back to legacy `strikePercentage` for backward compatibility.
  static int extractStrikePercentage(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) return StrikePercentage.none;
    final strikeCount = (data['strikeCount'] as num?)?.toInt();
    if (strikeCount != null) return strikeCount * 50;
    // Fallback: legacy documents that have strikePercentage
    return (data['strikePercentage'] as num?)?.toInt() ?? StrikePercentage.none;
  }

  static String extractAccountStatus(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) return AccountStatus.active.value;
    final strikeCount = (data['strikeCount'] as num?)?.toInt();
    if (strikeCount != null) {
      return strikeCount >= 2
          ? AccountStatus.suspended.value
          : AccountStatus.active.value;
    }
    // Fallback: legacy documents
    return data['accountStatus'] as String? ?? AccountStatus.active.value;
  }

  static int extractStrikeCount(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) return 0;
    return (data['strikeCount'] as num?)?.toInt() ?? 0;
  }

  // ── Business Logic ──────────────────────────────────────────────────────────

  /// Calculate the account status from a strike percentage.
  AccountStatus calculateAccountStatus(int strikePercentage) {
    return accountStatusFromPercentage(strikePercentage);
  }

  /// Pardon (reduce) a student's strike.
  ///
  /// Phase 6: Decrease strikeCount, never below zero.
  /// Percentage derived as strikeCount * 50.
  /// Automatically restore accountStatus = ACTIVE when strikeCount < 2.
  Future<String?> pardonStrike({
    required String studentId,
    required String adminId,
    String reason = 'Strike pardoned',
  }) async {
    try {
      final docRef = _firestore.collection('users').doc(studentId);

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);

        if (!doc.exists) {
          throw StateError('Student not found.');
        }

        final currentCount =
            (doc.data()?['strikeCount'] as num?)?.toInt() ?? 0;
        final newCount = currentCount > 0 ? currentCount - 1 : 0;
        final newPercentage = newCount * 50;

        transaction.update(docRef, {
          'strikeCount': newCount,
          'accountStatus': accountStatusFromPercentage(newPercentage).value,
          'lastPardonAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final auditRef = _firestore.collection('audit_logs').doc();
        transaction.set(auditRef, {
          'studentId': studentId,
          'adminId': adminId,
          'action': StrikeAction.pardon.value,
          'previousStrike': currentCount * 50,
          'newStrike': newPercentage,
          'reason': reason,
          'timestamp': FieldValue.serverTimestamp(),
        });
      });

      return null; // success
    } catch (e, stack) {
      if (e is StateError) return e.message;
      debugPrint('[StrikeService] pardonStrike error: $e');
      debugPrint('[StrikeService] stack: $stack');
      return 'Failed to pardon strike. Please try again.';
    }
  }

  /// Reset a student's strikes to 0.
  Future<String?> resetStrike({
    required String studentId,
    required String adminId,
    String reason = 'Strikes reset by admin',
  }) async {
    try {
      final docRef = _firestore.collection('users').doc(studentId);

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);

        if (!doc.exists) {
          throw StateError('Student not found.');
        }

        transaction.update(docRef, {
          'strikeCount': 0,
          'accountStatus': AccountStatus.active.value,
          'lastPardonAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final auditRef = _firestore.collection('audit_logs').doc();
        transaction.set(auditRef, {
          'studentId': studentId,
          'adminId': adminId,
          'action': StrikeAction.reset.value,
          'previousStrike': ((doc.data()?['strikeCount'] as num?)?.toInt() ?? 0) * 50,
          'newStrike': 0,
          'reason': reason,
          'timestamp': FieldValue.serverTimestamp(),
        });
      });

      return null; // success
    } catch (e, stack) {
      if (e is StateError) return e.message;
      debugPrint('[StrikeService] resetStrike error: $e');
      debugPrint('[StrikeService] stack: $stack');
      return 'Failed to reset strikes. Please try again.';
    }
  }

  /// Reactivate a suspended student account (resets strikes to 0).
  Future<String?> reactivateAccount({
    required String studentId,
    required String adminId,
    String reason = 'Account reactivated by admin',
  }) async {
    try {
      final docRef = _firestore.collection('users').doc(studentId);

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);

        if (!doc.exists) {
          throw StateError('Student not found.');
        }

        transaction.update(docRef, {
          'strikeCount': 0,
          'accountStatus': AccountStatus.active.value,
          'lastPardonAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final auditRef = _firestore.collection('audit_logs').doc();
        transaction.set(auditRef, {
          'studentId': studentId,
          'adminId': adminId,
          'action': StrikeAction.reactivate.value,
          'previousStrike': ((doc.data()?['strikeCount'] as num?)?.toInt() ?? 0) * 50,
          'newStrike': 0,
          'reason': reason,
          'timestamp': FieldValue.serverTimestamp(),
        });
      });

      return null; // success
    } catch (e, stack) {
      if (e is StateError) return e.message;
      debugPrint('[StrikeService] reactivateAccount error: $e');
      debugPrint('[StrikeService] stack: $stack');
      return 'Failed to reactivate account. Please try again.';
    }
  }
}
