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
  static int extractStrikePercentage(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) return StrikePercentage.none;
    return (data['strikePercentage'] as num?)?.toInt() ?? StrikePercentage.none;
  }

  static String extractAccountStatus(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) return AccountStatus.active.value;
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

  /// Issue a strike to the student.
  ///
  /// Rules:
  ///   0 → 50
  ///   50 → 100
  ///   100 → 100
  Future<String?> issueStrike({
    required String studentId,
    required String adminId,
    String reason = 'Order not collected',
  }) async {
    try {
      final docRef = _firestore.collection('users').doc(studentId);

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);

        if (!doc.exists) {
          throw StateError('Student not found.');
        }

        final currentPercentage =
            (doc.data()?['strikePercentage'] as num?)?.toInt() ?? 0;
        final newPercentage = _nextStrikePercentage(currentPercentage);

        transaction.update(docRef, {
          'strikePercentage': newPercentage,
          'strikeCount': FieldValue.increment(1),
          'accountStatus': accountStatusFromPercentage(newPercentage).value,
          'lastStrikeAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final auditRef = _firestore.collection('audit_logs').doc();
        transaction.set(auditRef, {
          'studentId': studentId,
          'adminId': adminId,
          'action': StrikeAction.issueStrike.value,
          'previousStrike': currentPercentage,
          'newStrike': newPercentage,
          'reason': reason,
          'timestamp': FieldValue.serverTimestamp(),
        });
      });

      return null; // success
    } catch (e, stack) {
      if (e is StateError) return e.message;
      debugPrint('[StrikeService] issueStrike error: $e');
      debugPrint('[StrikeService] stack: $stack');
      return 'Failed to issue strike. Please try again.';
    }
  }

  /// Pardon (reduce) a student's strike.
  ///
  /// Rules:
  ///   100 → 50
  ///   50 → 0
  ///   0 → 0
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

        final currentPercentage =
            (doc.data()?['strikePercentage'] as num?)?.toInt() ?? 0;
        final newPercentage = _previousStrikePercentage(currentPercentage);

        transaction.update(docRef, {
          'strikePercentage': newPercentage,
          'accountStatus': accountStatusFromPercentage(newPercentage).value,
          'lastPardonAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final auditRef = _firestore.collection('audit_logs').doc();
        transaction.set(auditRef, {
          'studentId': studentId,
          'adminId': adminId,
          'action': StrikeAction.pardon.value,
          'previousStrike': currentPercentage,
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

  /// Reset a student's strikes to 0%.
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

        final currentPercentage =
            (doc.data()?['strikePercentage'] as num?)?.toInt() ?? 0;

        transaction.update(docRef, {
          'strikePercentage': StrikePercentage.none,
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
          'previousStrike': currentPercentage,
          'newStrike': StrikePercentage.none,
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

  /// Suspend a student's account (sets strike to 100%).
  Future<String?> suspendAccount({
    required String studentId,
    required String adminId,
    String reason = 'Account suspended by admin',
  }) async {
    try {
      final docRef = _firestore.collection('users').doc(studentId);

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);

        if (!doc.exists) {
          throw StateError('Student not found.');
        }

        final currentPercentage =
            (doc.data()?['strikePercentage'] as num?)?.toInt() ?? 0;

        transaction.update(docRef, {
          'strikePercentage': StrikePercentage.suspended,
          'accountStatus': AccountStatus.suspended.value,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final auditRef = _firestore.collection('audit_logs').doc();
        transaction.set(auditRef, {
          'studentId': studentId,
          'adminId': adminId,
          'action': StrikeAction.suspend.value,
          'previousStrike': currentPercentage,
          'newStrike': StrikePercentage.suspended,
          'reason': reason,
          'timestamp': FieldValue.serverTimestamp(),
        });
      });

      return null; // success
    } catch (e, stack) {
      if (e is StateError) return e.message;
      debugPrint('[StrikeService] suspendAccount error: $e');
      debugPrint('[StrikeService] stack: $stack');
      return 'Failed to suspend account. Please try again.';
    }
  }

  /// Reactivate a suspended student account (resets strike to 0%).
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

        final currentPercentage =
            (doc.data()?['strikePercentage'] as num?)?.toInt() ?? 0;

        transaction.update(docRef, {
          'strikePercentage': StrikePercentage.none,
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
          'previousStrike': currentPercentage,
          'newStrike': StrikePercentage.none,
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

  // ── Private Helpers ─────────────────────────────────────────────────────────

  /// Issue strike logic:
  ///   0 → 50
  ///   50 → 100
  ///   100 → 100
  int _nextStrikePercentage(int current) {
    if (current >= StrikePercentage.suspended) {
      return StrikePercentage.suspended;
    } else if (current >= StrikePercentage.warning) {
      return StrikePercentage.suspended;
    }
    return StrikePercentage.warning;
  }

  /// Pardon logic:
  ///   100 → 50
  ///   50 → 0
  ///   0 → 0
  int _previousStrikePercentage(int current) {
    if (current >= StrikePercentage.suspended) {
      return StrikePercentage.warning;
    } else if (current >= StrikePercentage.warning) {
      return StrikePercentage.none;
    }
    return StrikePercentage.none;
  }
}
