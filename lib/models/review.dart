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

/// Predefined review tags that students can select.
///
/// Maximum 5 tags per review.
const List<String> reviewTemplateTags = [
  'Great deal',
  'Great value for money',
  'Hot food',
  'Served well',
  'Fresh ingredients',
  'Very delicious',
  'Fast preparation',
  'Large portion',
  'Friendly service',
  'Worth the price',
  'Would order again',
  'Not great as expected',
  'Too salty',
  'Too spicy',
  'Too cold',
  'Small portion',
  'Late preparation',
  'Not good at all',
];

/// Represents a single food review created after a collected order.
class Review {
  final String id;
  final String foodId;
  final String orderId;
  final String userId;
  final String displayName;
  final bool anonymous;
  final int rating;
  final List<String> templateTags;
  final String comment;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool deleted;
  final DateTime? deletedAt;
  final bool verifiedPurchase;

  const Review({
    this.id = '',
    required this.foodId,
    required this.orderId,
    required this.userId,
    this.displayName = 'CampusBite Customer',
    this.anonymous = true,
    this.rating = 5,
    this.templateTags = const [],
    this.comment = '',
    this.createdAt,
    this.updatedAt,
    this.deleted = false,
    this.deletedAt,
    this.verifiedPurchase = true,
  });

  /// Build a [Review] from a Firestore document snapshot.
  factory Review.fromFirestore(String docId, Object? data) {
    if (data is! Map<String, dynamic>) {
      return Review(id: docId, foodId: '', orderId: '', userId: '');
    }
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      try {
        return (value as dynamic).toDate() as DateTime;
      } on Exception catch (_) {}
      return null;
    }

    List<String> parseStringList(dynamic value) {
      if (value == null) return [];
      if (value is List) return value.map((e) => e.toString()).toList();
      return [];
    }

    return Review(
      id: docId,
      foodId: data['foodId'] as String? ?? '',
      orderId: data['orderId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'CampusBite Customer',
      anonymous: data['anonymous'] as bool? ?? true,
      rating: ((data['rating'] as num?)?.toInt() ?? 5).clamp(1, 5).toInt(),
      templateTags: parseStringList(data['templateTags']),
      comment: data['comment'] as String? ?? '',
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
      deleted: data['deleted'] as bool? ?? false,
      deletedAt: parseTimestamp(data['deletedAt']),
      verifiedPurchase: data['verifiedPurchase'] as bool? ?? true,
    );
  }

  /// Serialize this review for Firestore creation.
  Map<String, dynamic> toFirestore() {
    return {
      'foodId': foodId,
      'orderId': orderId,
      'userId': userId,
      'displayName': displayName,
      'anonymous': anonymous,
      'rating': rating,
      'templateTags': templateTags,
      'comment': comment,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'deleted': false,
      'deletedAt': null,
      'verifiedPurchase': true,
    };
  }

  /// Serialize this review for Firestore update.
  Map<String, dynamic> toUpdateMap() {
    return {
      'rating': rating,
      'templateTags': templateTags,
      'comment': comment,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Create a copy with optional field overrides.
  Review copyWith({
    String? id,
    String? foodId,
    String? orderId,
    String? userId,
    String? displayName,
    bool? anonymous,
    int? rating,
    List<String>? templateTags,
    String? comment,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? deleted,
    DateTime? deletedAt,
    bool? verifiedPurchase,
  }) {
    return Review(
      id: id ?? this.id,
      foodId: foodId ?? this.foodId,
      orderId: orderId ?? this.orderId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      anonymous: anonymous ?? this.anonymous,
      rating: rating ?? this.rating,
      templateTags: templateTags ?? this.templateTags,
      comment: comment ?? this.comment,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      deletedAt: deletedAt ?? this.deletedAt,
      verifiedPurchase: verifiedPurchase ?? this.verifiedPurchase,
    );
  }

  /// The display name to show on the review card.
  String get displayNameForCard =>
      anonymous ? 'CampusBite Customer' : displayName;
}
