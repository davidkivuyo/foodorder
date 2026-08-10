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

/// Enumeration of all supported notification types.
///
/// Each value corresponds to a specific business event.
/// The [value] getter returns the Firestore-safe string representation.
enum NotificationType {
  orderAccepted,
  orderPreparing,
  orderReady,
  pickupReminder,
  orderNoShow,
  orderCancelled,
  accountSuspended,
  accountReactivated,
  newOrder,
  /// Fallback for notification types this app no longer handles (e.g.
  /// STRIKE_ISSUED/STRIKE_REMOVED produced by the admin app's strike
  /// engine). Kept parseable so the notification feed never breaks.
  notice;

  String get value {
    switch (this) {
      case NotificationType.orderAccepted:
        return 'ORDER_ACCEPTED';
      case NotificationType.orderPreparing:
        return 'ORDER_PREPARING';
      case NotificationType.orderReady:
        return 'ORDER_READY';
      case NotificationType.pickupReminder:
        return 'PICKUP_REMINDER';
      case NotificationType.orderNoShow:
        return 'ORDER_NO_SHOW';
      case NotificationType.orderCancelled:
        return 'ORDER_CANCELLED';
      case NotificationType.accountSuspended:
        return 'ACCOUNT_SUSPENDED';
      case NotificationType.accountReactivated:
        return 'ACCOUNT_REACTIVATED';
      case NotificationType.newOrder:
        return 'NEW_ORDER';
      case NotificationType.notice:
        return 'NOTICE';
    }
  }

  static NotificationType fromString(String value) {
    switch (value) {
      case 'ORDER_ACCEPTED':
        return NotificationType.orderAccepted;
      case 'ORDER_PREPARING':
        return NotificationType.orderPreparing;
      case 'ORDER_READY':
        return NotificationType.orderReady;
      case 'PICKUP_REMINDER':
        return NotificationType.pickupReminder;
      case 'ORDER_NO_SHOW':
        return NotificationType.orderNoShow;
      case 'ORDER_CANCELLED':
        return NotificationType.orderCancelled;
      case 'ACCOUNT_SUSPENDED':
        return NotificationType.accountSuspended;
      case 'ACCOUNT_REACTIVATED':
        return NotificationType.accountReactivated;
      case 'NEW_ORDER':
        return NotificationType.newOrder;
      default:
        // Unknown/legacy types (e.g. STRIKE_ISSUED/STRIKE_REMOVED from the
        // admin app) fall back to a generic notice instead of crashing the
        // notification feed.
        return NotificationType.notice;
    }
  }

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case NotificationType.orderAccepted:
        return 'Order Accepted';
      case NotificationType.orderPreparing:
        return 'Order Preparing';
      case NotificationType.orderReady:
        return 'Order Ready';
      case NotificationType.pickupReminder:
        return 'Pickup Reminder';
      case NotificationType.orderNoShow:
        return 'Order No Show';
      case NotificationType.orderCancelled:
        return 'Order Cancelled';
      case NotificationType.accountSuspended:
        return 'Account Suspended';
      case NotificationType.accountReactivated:
        return 'Account Reactivated';
      case NotificationType.newOrder:
        return 'New Order';
      case NotificationType.notice:
        return 'Notice';
    }
  }
}

/// Represents a single notification document from the Firestore
/// `notifications` collection.
///
/// Fields match the Phase 7 document schema exactly.
class NotificationModel {
  final String id;
  final String recipientId;
  final String recipientRole;
  final NotificationType type;
  final String title;
  final String message;
  final String? orderId;
  final String? eventId;
  final String? deepLink;
  final Map<String, dynamic>? metadata;
  final bool read;
  final DateTime? readAt;
  final bool deleted;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final String createdBy;

  NotificationModel({
    required this.id,
    required this.recipientId,
    required this.recipientRole,
    required this.type,
    required this.title,
    required this.message,
    this.orderId,
    this.eventId,
    this.deepLink,
    this.metadata,
    this.read = false,
    this.readAt,
    this.deleted = false,
    this.deletedAt,
    DateTime? createdAt,
    required this.createdBy,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Build from a Firestore document snapshot.
  factory NotificationModel.fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      try {
        return (value as dynamic).toDate() as DateTime;
      } on Exception catch (_) {
        return null;
      }
    }

    return NotificationModel(
      id: docId,
      recipientId: data['recipientId'] as String? ?? '',
      recipientRole: data['recipientRole'] as String? ?? 'student',
      type: NotificationType.fromString(
        data['type'] as String? ?? 'ORDER_ACCEPTED',
      ),
      title: data['title'] as String? ?? '',
      message: data['message'] as String? ?? '',
      orderId: data['orderId'] as String?,
      eventId: data['eventId'] as String?,
      deepLink: data['deepLink'] as String?,
      metadata: data['metadata'] is Map
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : null,
      read: data['read'] as bool? ?? false,
      readAt: parseTimestamp(data['readAt']),
      deleted: data['deleted'] as bool? ?? false,
      deletedAt: parseTimestamp(data['deletedAt']),
      createdAt: parseTimestamp(data['createdAt']) ?? DateTime.now(),
      createdBy: data['createdBy'] as String? ?? 'system',
    );
  }

  /// Serialize to a Firestore-compatible map (for creation).
  Map<String, dynamic> toFirestore() {
    return {
      'recipientId': recipientId,
      'recipientRole': recipientRole,
      'type': type.value,
      'title': title,
      'message': message,
      if (orderId != null) 'orderId': orderId,
      if (eventId != null) 'eventId': eventId,
      if (deepLink != null) 'deepLink': deepLink,
      if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
      'read': false,
      'readAt': null,
      'deleted': false,
      'deletedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
    };
  }
}
