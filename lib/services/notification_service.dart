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

import 'package:flutter/foundation.dart' show visibleForTesting;
import '../models/notification_model.dart';
import '../repositories/notification_repository.dart';
import 'app_log.dart';

/// Service that manages notification business logic.
///
/// Responsibilities:
/// - Create notifications with duplicate prevention
/// - Mark notifications as read / all as read
/// - Soft-delete notifications
/// - Expose reactive streams
///
/// Business logic must NEVER exist inside widgets.
/// Cloud Functions and backend services should call this service only.
///
/// Designed for future FCM integration — the delivery abstraction is
/// contained within this service so no business code needs changing
/// when push notifications are added.
class NotificationService {
  /// The recipient role value used for student notifications.
  static const String roleStudent = 'student';

  /// The recipient role value used for admin notifications.
  static const String roleAdmin = 'admin';

  final NotificationRepository _repository;

  NotificationService({NotificationRepository? repository})
      : _repository = repository ?? NotificationRepository();

  // ── Streams ────────────────────────────────────────────────────────────────

  /// Stream of notifications for a specific recipient.
  Stream<List<NotificationModel>> notificationsStream({
    required String recipientId,
    required String recipientRole,
    int limit = 50,
  }) {
    return _repository.notificationsStream(
      recipientId: recipientId,
      recipientRole: recipientRole,
      limit: limit,
    );
  }

  /// Stream of unread notification count.
  Stream<int> unreadCountStream({
    required String recipientId,
    required String recipientRole,
  }) {
    return _repository.unreadCountStream(
      recipientId: recipientId,
      recipientRole: recipientRole,
    );
  }

  // ── Create (with duplicate prevention) ─────────────────────────────────────

  /// Create a notification with idempotent duplicate prevention.
  ///
  /// If a notification with the same [eventId] already exists, creation is
  /// skipped. This ensures exactly one notification per business event.
  ///
  /// Returns the notification ID if created, `null` if skipped or failed.
  Future<String?> createNotification({
    required String recipientId,
    required String recipientRole,
    required NotificationType type,
    required String title,
    required String message,
    String? orderId,
    String? eventId,
    String? deepLink,
    Map<String, dynamic>? metadata,
    String createdBy = 'system',
  }) async {
    // Duplicate prevention: skip if eventId already exists
    if (eventId != null && eventId.isNotEmpty) {
      final exists = await _repository.existsByEventId(eventId);
      if (exists) {
        AppLog.d('[NotificationService] Skipping duplicate notification: $eventId');
        return null;
      }
    }

    final data = NotificationModel(
      id: '', // Will be assigned by Firestore
      recipientId: recipientId,
      recipientRole: recipientRole,
      type: type,
      title: title,
      message: message,
      orderId: orderId,
      eventId: eventId,
      deepLink: deepLink,
      metadata: metadata,
      createdBy: createdBy,
    ).toFirestore();

    if (eventId != null && eventId.isNotEmpty) {
      // Deterministic doc ID — a concurrent delivery of the same event
      // writes to the same document, so at most one notification per event.
      return await _repository.createWithEventId(eventId, data);
    }
    return await _repository.create(data);
  }

  // ── Read status ────────────────────────────────────────────────────────────

  /// Mark a single notification as read.
  ///
  /// Updates ONLY `read` and `readAt` — never rewrites the document.
  Future<bool> markAsRead(String notificationId) async {
    return await _repository.markAsRead(notificationId);
  }

  /// Mark all unread notifications for a recipient as read.
  ///
  /// Batch update — does not rewrite already-read notifications.
  Future<bool> markAllAsRead({
    required String recipientId,
    required String recipientRole,
  }) async {
    return await _repository.markAllAsRead(
      recipientId: recipientId,
      recipientRole: recipientRole,
    );
  }

  // ── Soft delete ────────────────────────────────────────────────────────────

  /// Soft-delete a single notification.
  ///
  /// Sets `deleted = true` and `deletedAt`. The notification is hidden
  /// from queries but preserved in Firestore for the cleanup function.
  Future<bool> softDelete(String notificationId) async {
    return await _repository.softDelete(notificationId);
  }

  /// Clear all notifications for a recipient (soft delete).
  Future<bool> clearAll({
    required String recipientId,
    required String recipientRole,
  }) async {
    return await _repository.clearAll(
      recipientId: recipientId,
      recipientRole: recipientRole,
    );
  }

  // ── Future delivery abstraction ────────────────────────────────────────────

  /// Placeholder for future FCM delivery.
  ///
  /// When FCM is added, this method will handle push delivery WITHOUT
  /// modifying the calling code. Business services will still call
  /// [createNotification] and FCM delivery happens transparently.
  @visibleForTesting
  Future<void> deliverPushNotification({
    required String recipientId,
    required String title,
    required String message,
    Map<String, String>? data,
  }) async {
    // Phase 8 — Firebase Cloud Messaging integration planned
    // This method will:
    // 1. Fetch the recipient's FCM token from Firestore
    // 2. Send push notification via Firebase Admin SDK / Cloud Function
    // 3. Record delivery status for analytics
    AppLog.d('[NotificationService] Push delivery placeholder: $title — $message');
  }
}
