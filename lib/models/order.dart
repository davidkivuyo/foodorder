import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/food_data.dart';
import 'cart_item.dart';

/// Represents the current state of an order.
enum OrderStatus {
  pending,    // Awaiting admin review
  accepted,   // Admin accepted the order
  rejected,   // Admin rejected the order
  preparing,  // Food is being cooked
  ready,      // Ready for pickup
  collected,  // Student collected the order
  noShow;     // Student did not collect

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
  final int pickupWindowMinutes;
  final DeadlineStatus deadlineStatus;

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
    this.pickupWindowMinutes = 20,
    this.deadlineStatus = DeadlineStatus.notReady,
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
          return CartItem(
            id: itemMap['foodItemId'] ?? '',
            foodItem: FoodItem.fromMap(itemMap as Map<String, dynamic>),
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
            return CartItem(
              id: itemMap['foodItemId'] ?? '',
              foodItem: FoodItem.fromMap(itemMap as Map<String, dynamic>),
              quantity: (itemMap['quantity'] as num?)?.toInt() ?? 1,
              selectedCafe: itemMap['selectedCafe'] as String?,
            );
          }).toList();
        } catch (_) {}
      }
      return [];
    }

    // Parse timestamp fields
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      try {
        return (value as dynamic).toDate() as DateTime;
      } catch (_) {}
      return null;
    }

    return FoodOrder(
      orderId: snapshot.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      items: parseItems(data['items']),
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
      orderTime: parseTimestamp(data['createdAt']) ?? DateTime.now(),
      status: OrderStatus.fromString(data['status'] as String? ?? 'pending'),
      updatedAt: parseTimestamp(data['updatedAt']),
      readyAt: parseTimestamp(data['readyAt']),
      pickupDeadline: parseTimestamp(data['pickupDeadline']),
      pickupWindowMinutes: (data['pickupWindowMinutes'] as num?)?.toInt() ?? 20,
      deadlineStatus: DeadlineStatus.fromString(
        data['deadlineStatus'] as String? ?? 'NOT_READY',
      ),
    );
  }

  /// Serialize this [FoodOrder] to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    return {
      'orderId': orderId,
      'userId': userId,
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
      'totalAmount': totalAmount,
      'status': status.toShortString(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'deadlineStatus': DeadlineStatus.notReady.toShortString(),
    };
  }
}

