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

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/food_data.dart';
import '../services/pickup_deadline_service.dart';
import 'cart_item.dart';

/// Represents the current state of an order.
enum OrderStatus {
  pending,    // Awaiting admin review (cancellable during the 2-min window)
  accepted,   // Admin accepted the order
  rejected,   // Admin rejected the order
  preparing,  // Food is being cooked
  ready,      // Ready for pickup
  collected,  // Student collected the order
  noShow,     // Student did not collect
  cancelled;  // Student cancelled within the cancellation window (terminal)

  /// Parse an [OrderStatus] from its string representation.
  static OrderStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return OrderStatus.pending;
      case 'accepted':
        return OrderStatus.accepted;
      case 'rejected':
        return OrderStatus.rejected;
      case 'preparing':
        return OrderStatus.preparing;
      case 'ready':
        return OrderStatus.ready;
      case 'collected':
        return OrderStatus.collected;
      case 'no_show':
        return OrderStatus.noShow;
      case 'cancelled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.pending;
    }
  }

  /// Serialize this [OrderStatus] to its Firestore string value.
  String toShortString() {
    switch (this) {
      case OrderStatus.noShow:
        return 'no_show';
      default:
        return name;
    }
  }
}

/// Backend-driven pickup deadline status.
/// Only the Cloud Function writes these values.
enum DeadlineStatus {
  notReady,
  active,
  collected,
  expired;

  static DeadlineStatus fromString(String value) {
    switch (value) {
      case 'NOT_READY':
        return DeadlineStatus.notReady;
      case 'ACTIVE':
        return DeadlineStatus.active;
      case 'COLLECTED':
        return DeadlineStatus.collected;
      case 'EXPIRED':
        return DeadlineStatus.expired;
      default:
        return DeadlineStatus.notReady;
    }
  }

  String toShortString() {
    switch (this) {
      case DeadlineStatus.notReady:
        return 'NOT_READY';
      case DeadlineStatus.active:
        return 'ACTIVE';
      case DeadlineStatus.collected:
        return 'COLLECTED';
      case DeadlineStatus.expired:
        return 'EXPIRED';
    }
  }
}

/// Represents a food order placed by a student.
class FoodOrder {
  final String orderId;
  final String userId;
  final String userName;
  final List<CartItem> items;
  final double totalAmount;
  final DateTime orderTime;
  OrderStatus status;
  final DateTime? updatedAt;
  final DateTime? readyAt;
  final DateTime? pickupDeadline;
  final DateTime? collectedAt;
  final int pickupWindowMinutes;
  final DeadlineStatus deadlineStatus;

  // Phase 5: Distance-aware pickup window
  final GeoPoint? studentLocation;
  final GeoPoint? cafeLocation;
  final String? cafeId;
  final double? distanceMeters;
  final bool distanceCalculated;

  // No-show processing state (server-written by the pickup expiry function)
  final bool noShowProcessed;
  final DateTime? noShowAt;
  final DateTime? expiredAt;

  // Pickup deadline extension (student-initiated, once per order)
  final bool deadlineExtended;
  final DateTime? extensionAt;

  // Phase B: 2-minute cancellation window (server-authoritative)
  final DateTime? cancellationDeadline;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancellationReason;

  /// Calculated server-authoritative hard cutoff time for pickup eligibility.
  DateTime? get noShowEligibleAt => pickupDeadline?.add(
      const Duration(minutes: PickupDeadlineService.defaultGracePeriodMinutes));

  FoodOrder({
    required this.orderId,
    required this.userId,
    required this.userName,
    required this.items,
    required this.totalAmount,
    required this.orderTime,
    this.status = OrderStatus.pending,
    this.updatedAt,
    this.readyAt,
    this.pickupDeadline,
    this.collectedAt,
    this.pickupWindowMinutes = 20,
    this.deadlineStatus = DeadlineStatus.notReady,
    this.studentLocation,
    this.cafeLocation,
    this.cafeId,
    this.distanceMeters,
    this.distanceCalculated = false,
    this.noShowProcessed = false,
    this.noShowAt,
    this.expiredAt,
    this.deadlineExtended = false,
    this.extensionAt,
    this.cancellationDeadline,
    this.cancelledAt,
    this.cancelledBy,
    this.cancellationReason,
  });

  /// Build a [FoodOrder] from a Firestore document snapshot.
  factory FoodOrder.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data()!;

    // Parse items list stored as a JSON string or a list of maps
    List<CartItem> parseItems(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) {
        return raw.map((itemMap) {
          final foodItemId = itemMap['foodItemId'] as String? ?? itemMap['id'] as String? ?? '';
          return CartItem(
            id: foodItemId,
            foodItem: FoodItem.fromMap(
              itemMap as Map<String, dynamic>,
              id: foodItemId,
            ),
            quantity: (itemMap['quantity'] as num?)?.toInt() ?? 1,
            selectedCafe: itemMap['selectedCafe'] as String?,
          );
        }).toList();
      }
      // Fallback: try JSON-decoding a string
      if (raw is String) {
        try {
          final decoded = jsonDecode(raw) as List;
          return decoded.map((itemMap) {
            final foodItemId = itemMap['foodItemId'] as String? ?? itemMap['id'] as String? ?? '';
            return CartItem(
              id: foodItemId,
              foodItem: FoodItem.fromMap(
                itemMap as Map<String, dynamic>,
                id: foodItemId,
              ),
              quantity: (itemMap['quantity'] as num?)?.toInt() ?? 1,
              selectedCafe: itemMap['selectedCafe'] as String?,
            );
          }).toList();
        } on Exception catch (_) {}
      }
      return [];
    }

    // Parse timestamp fields
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      try {
        return (value as dynamic).toDate() as DateTime;
      } on Exception catch (_) {}
      return null;
    }

    // Parse GeoPoint fields (safely handle null / wrong type)
    GeoPoint? parseGeoPoint(dynamic value) {
      if (value == null) return null;
      if (value is GeoPoint) return value;
      return null;
    }

    return FoodOrder(
      orderId: snapshot.id,
      userId: data['studentId'] as String? ?? data['userId'] as String? ?? '',
      userName: data['userName'] ?? '',
      items: parseItems(data['items']),
      totalAmount: (data['price'] as num?)?.toDouble() ?? (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
      orderTime: parseTimestamp(data['createdAt']) ?? DateTime.now(),
      status: OrderStatus.fromString(data['status'] as String? ?? 'pending'),
      updatedAt: parseTimestamp(data['updatedAt']),
      readyAt: parseTimestamp(data['readyAt']),
      pickupDeadline: parseTimestamp(data['pickupDeadline']),
      collectedAt: parseTimestamp(data['collectedAt']),
      pickupWindowMinutes: (data['pickupWindowMinutes'] as num?)?.toInt() ?? 20,
      deadlineStatus: DeadlineStatus.fromString(
        data['deadlineStatus'] as String? ?? 'NOT_READY',
      ),
      studentLocation: parseGeoPoint(data['studentLocation']),
      cafeLocation: parseGeoPoint(data['cafeLocation']),
      cafeId: (data['cafeId'] as String?) ?? '',
      distanceMeters: (data['distanceMeters'] as num?)?.toDouble(),
      distanceCalculated: data['distanceCalculated'] as bool? ?? false,
      noShowProcessed: data['noShowProcessed'] as bool? ?? false,
      noShowAt: parseTimestamp(data['noShowAt']),
      expiredAt: parseTimestamp(data['expiredAt']),
      deadlineExtended: data['deadlineExtended'] as bool? ?? false,
      extensionAt: parseTimestamp(data['extensionAt']),
      cancellationDeadline: parseTimestamp(data['cancellationDeadline']),
      cancelledAt: parseTimestamp(data['cancelledAt']),
      cancelledBy: data['cancelledBy'] as String?,
      cancellationReason: data['cancellationReason'] as String?,
    );
  }

  /// Serialize this [FoodOrder] to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    return {
      'orderId': orderId,
      'studentId': userId,
      'userName': userName,
      'items': items
          .map(
            (item) => {
              'foodItemId': item.foodItem.id,
              'title': item.foodItem.title,
              'price': item.foodItem.price,
              'quantity': item.quantity,
              'image': item.foodItem.image,
              'selectedCafe': item.selectedCafe,
            },
          )
          .toList(),
      // Denormalised list of purchased food IDs so the review-eligibility
      // security rule can verify (via list.hasAny) that the reviewed food
      // was actually in the collected order. Firestore rules cannot
      // iterate over the nested `items` maps.
      'foodIds': items.map((item) => item.foodItem.id).toList(),
      'price': totalAmount,
      'cafeId': cafeId,
      'status': status.toShortString(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'deadlineStatus': DeadlineStatus.notReady.toShortString(),
      'cafeLocation': cafeLocation,
      'distanceMeters': distanceMeters,
      'distanceCalculated': distanceCalculated,
      'pickupWindowMinutes': pickupWindowMinutes,
      'noShowProcessed': noShowProcessed,
      'deadlineExtended': deadlineExtended,
      // Phase B: the authoritative cancellationDeadline (createdAt + 2 min)
      // is written only by the onNewOrder Cloud Function. The client never
      // sends one on create — the Firestore create rule rejects any payload
      // carrying it, so the deadline cannot be forged.
      'cancelledAt': cancelledAt,
      'cancelledBy': cancelledBy,
      'cancellationReason': cancellationReason,
    };
  }
}
