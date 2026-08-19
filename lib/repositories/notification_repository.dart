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
import '../models/notification_model.dart';
import '../services/app_log.dart';

/// Data-access layer for the Firestore `notifications` collection.
///
/// Handles all Firestore read/write operations.
/// No business logic — that lives in [NotificationService].
class NotificationRepository {
  final FirebaseFirestore _firestore;

  static const String _collection = 'notifications';

  NotificationRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Streams ────────────────────────────────────────────────────────────────

  /// Stream of notifications for a specific recipient.
  ///
  /// Filters by [recipientId], [recipientRole], `deleted == false`.
  /// Ordered by `createdAt` descending, limited to [limit] items.
  Stream<List<NotificationModel>> notificationsStream({
    required String recipientId,
    required String recipientRole,
    int limit = 50,
  }) {
    return _firestore
        .collection(_collection)
        .where('recipientId', isEqualTo: recipientId)
        .where('recipientRole', isEqualTo: recipientRole)
        .where('deleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return NotificationModel.fromFirestore(doc.id, doc.data());
          }).toList();
        });
  }

  /// Stream of unread notification count for a recipient.
  Stream<int> unreadCountStream({
    required String recipientId,
    required String recipientRole,
  }) {
    return _firestore
        .collection(_collection)
        .where('recipientId', isEqualTo: recipientId)
        .where('recipientRole', isEqualTo: recipientRole)
        .where('deleted', isEqualTo: false)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// Check if a notification with the given [eventId] already exists.
  Future<bool> existsByEventId(String eventId) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('eventId', isEqualTo: eventId)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  // ── Writes ─────────────────────────────────────────────────────────────────

  /// Create a new notification document.
  ///
  /// Returns the document ID of the created notification, or `null` on failure.
  Future<String?> create(Map<String, dynamic> data) async {
    try {
      final docRef = await _firestore.collection(_collection).add(data);
      return docRef.id;
    } on Exception catch (e) {
      AppLog.e('[NotificationRepository] create error', e);
      return null;
    }
  }

  /// Create a notification under a deterministic document ID derived from
  /// [eventId], so concurrent deliveries of the same event cannot produce
  /// duplicate documents.
  ///
  /// The write runs inside a transaction that reads the target document
  /// first: it is created only when it does not already exist, and an
  /// existing document is never overwritten (returns `null`, matching the
  /// duplicate-skip behaviour of the service pre-check). A concurrent writer
  /// that wins the race causes this transaction to retry and observe the
  /// existing document, so at most one notification exists per eventId.
  ///
  /// Returns the document ID of the created notification, `null` when it
  /// already exists, or `null` on failure.
  Future<String?> createWithEventId(
    String eventId,
    Map<String, dynamic> data,
  ) async {
    try {
      final docRef = _firestore
          .collection(_collection)
          .doc(_sanitizeEventId(eventId));
      var created = false;
      await _firestore.runTransaction<void>((tx) async {
        // Reset per attempt: a retry must not inherit the previous attempt's
        // flag — the final attempt's read decides the outcome.
        created = false;
        final snapshot = await tx.get(docRef);
        if (snapshot.exists) {
          // Concurrent/redelivered duplicate — abort without overwriting.
          return;
        }
        tx.set(docRef, data);
        created = true;
      });
      if (!created) return null;
      return docRef.id;
    } on Exception catch (e) {
      AppLog.e('[NotificationRepository] createWithEventId error', e);
      return null;
    }
  }

  /// Map an eventId to a Firestore-safe document ID.
  ///
  /// Firestore document IDs may not contain `/` (and a few other reserved
  /// patterns); app-generated eventIds only contain letters, digits,
  /// underscores and hyphens, so this sanitisation is collision-free for
  /// them and merely guards against unusual caller-supplied values.
  static String _sanitizeEventId(String eventId) =>
      eventId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// Mark a single notification as read.
  Future<bool> markAsRead(String notificationId) async {
    try {
      await _firestore.collection(_collection).doc(notificationId).update({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on Exception catch (e) {
      AppLog.e('[NotificationRepository] markAsRead error', e);
      return false;
    }
  }

  /// Mark all unread notifications for a recipient as read.
  Future<bool> markAllAsRead({
    required String recipientId,
    required String recipientRole,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('recipientId', isEqualTo: recipientId)
          .where('recipientRole', isEqualTo: recipientRole)
          .where('deleted', isEqualTo: false)
          .where('read', isEqualTo: false)
          .get();

      if (snapshot.docs.isEmpty) return true;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      return true;
    } on Exception catch (e) {
      AppLog.e('[NotificationRepository] markAllAsRead error', e);
      return false;
    }
  }

  /// Soft-delete a notification.
  Future<bool> softDelete(String notificationId) async {
    try {
      await _firestore.collection(_collection).doc(notificationId).update({
        'deleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on Exception catch (e) {
      AppLog.e('[NotificationRepository] softDelete error', e);
      return false;
    }
  }

  /// Soft-delete all notifications for a recipient.
  Future<bool> clearAll({
    required String recipientId,
    required String recipientRole,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('recipientId', isEqualTo: recipientId)
          .where('recipientRole', isEqualTo: recipientRole)
          .where('deleted', isEqualTo: false)
          .get();

      if (snapshot.docs.isEmpty) return true;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'deleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      return true;
    } on Exception catch (e) {
      AppLog.e('[NotificationRepository] clearAll error', e);
      return false;
    }
  }
}
