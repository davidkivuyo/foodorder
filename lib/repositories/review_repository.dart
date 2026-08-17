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
import '../models/review.dart';

/// Data-access layer for the Firestore `reviews` collection.
///
/// Handles all Firestore read/write operations.
/// No business logic — that lives in [ReviewService].
class ReviewRepository {
  final FirebaseFirestore _firestore;

  static const String _collection = 'reviews';

  /// Deterministic per-(user, food) guard collection that makes "one live
  /// review per (student, food)" race-free. The guard document is claimed
  /// in the SAME transaction as the review (create/revive) and released on
  /// soft-delete, so two concurrent creates for the same meal via different
  /// orders cannot both pass.
  static const String _guardCollection = 'review_guards';

  ReviewRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  // ── Streams ────────────────────────────────────────────────────────────────

  /// Fixed page size enforced for every paginated review query.
  ///
  /// Caller-provided [limit] values are ignored — this repository always
  /// caps each page at this size so no caller can request an unbounded
  /// number of reviews in a single read.
  static const int _pageSize = 20;

  /// Stream of non-deleted reviews for a specific food item, paginated.
  ///
  /// [limit] controls how many reviews are returned per page, capped at
  /// [_pageSize] so no caller can request an unbounded number of reads.
  Stream<List<Review>> foodReviewsStream({
    required String foodId,
    int limit = _pageSize,
    DocumentSnapshot? lastDoc,
    String orderBy = 'createdAt',
    bool descending = true,
  }) {
    final effectiveLimit = limit.clamp(1, _pageSize);
    Query query = _firestore
        .collection(_collection)
        .where('foodId', isEqualTo: foodId)
        .where('deleted', isEqualTo: false)
        .orderBy(orderBy, descending: descending)
        .limit(effectiveLimit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Review.fromFirestore(doc.id, data);
      }).toList();
    });
  }

  /// One-shot fetch of reviews for a food item, with pagination support.
  ///
  /// [limit] controls how many reviews are returned per page, capped at
  /// [_pageSize] so no caller can request an unbounded number of reads.
  Future<MapEntry<List<Review>, DocumentSnapshot?>> fetchFoodReviews({
    required String foodId,
    int limit = _pageSize,
    DocumentSnapshot? lastDoc,
    String orderBy = 'createdAt',
    bool descending = true,
  }) async {
    final effectiveLimit = limit.clamp(1, _pageSize);
    Query query = _firestore
        .collection(_collection)
        .where('foodId', isEqualTo: foodId)
        .where('deleted', isEqualTo: false)
        .orderBy(orderBy, descending: descending)
        .limit(effectiveLimit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    final snapshot = await query.get();
    final reviews = snapshot.docs.map((doc) {
      final data = doc.data();
      return Review.fromFirestore(doc.id, data);
    }).toList();

    return MapEntry(reviews, snapshot.docs.lastOrNull);
  }

  /// Get all reviews (including soft-deleted) by a user for a specific food item.
  ///
  /// Includes soft-deleted reviews so the eligibility check in
  /// ReviewService matches the atomic create() constraint, which treats
  /// any existing document as already reviewed.
  Future<List<Review>> findUserReviewsForFood({
    required String foodId,
    required String userId,
  }) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('foodId', isEqualTo: foodId)
        .where('userId', isEqualTo: userId)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return Review.fromFirestore(doc.id, data);
    }).toList();
  }

  /// Find all collected order IDs that contain a specific food item.
  ///
  /// Matches both status casings the system has historically stored
  /// ('collected' and 'COLLECTED') so eligibility works regardless of
  /// which casing a collected order was written with.  Returns all
  /// matching orders without a fixed limit so the result is never
  /// silently truncated.  Throws on Firestore failure so callers can
  /// surface retryable errors rather than receiving an empty list that
  /// looks like a legitimate "no matches" result.
  Future<List<String>> findOrderIdsWithFoodItem({
    required String userId,
    required String foodId,
  }) async {
    final orderIds = <String>[];

    final snapshot = await _firestore
        .collection('orders')
        .where('studentId', isEqualTo: userId)
        .where('status', whereIn: ['collected', 'COLLECTED'])
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final items = data['items'];
      if (items is List) {
        for (final item in items) {
          if (item is Map) {
            final itemFoodId =
                item['foodItemId'] as String? ?? item['id'] as String? ?? '';
            if (itemFoodId == foodId) {
              orderIds.add(doc.id);
              break;
            }
          }
        }
      }
    }

    return orderIds;
  }

  /// Total count of non-deleted reviews for a food item.
  Future<int> countReviewsForFood(String foodId) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('foodId', isEqualTo: foodId)
        .where('deleted', isEqualTo: false)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  /// Fetch a single review by its document ID.
  ///
  /// Returns `null` when the document does not exist.  Firestore
  /// permission, network, or read failures propagate to the caller so
  /// they can be surfaced as retryable errors instead of being confused
  /// with a missing document.
  Future<Review?> getById(String reviewId) async {
    final doc = await _firestore.collection(_collection).doc(reviewId).get();
    if (!doc.exists) return null;
    return Review.fromFirestore(doc.id, doc.data()!);
  }

  /// Build a deterministic document ID from the (userId, orderId, foodId)
  /// composite key.
  ///
  /// Uses a plain `:`-separated encoding that the Firestore security rules
  /// can reproduce (`userId + ':' + orderId + ':' + foodId`) so the create
  /// rule can enforce "one review per (user, order, food)" structurally.
  /// The rules language cannot convert int to string (no `toString()`), so
  /// no length-prefix scheme is used here.  Firebase UIDs, order IDs
  /// (`CB-xxxx`) and food doc IDs never contain `:`, so the encoding is
  /// collision-free in practice.
  ///
  /// Reads ([findByCompositeKey]) and writes ([create]) must use the exact
  /// same encoding so each tuple maps to exactly one document.
  static String _compositeReviewId({
    required String userId,
    required String orderId,
    required String foodId,
  }) {
    return '$userId:$orderId:$foodId';
  }

  /// Build the deterministic (userId, foodId) guard document ID.
  ///
  /// Mirrors the `:`-encoding of [_compositeReviewId] so the rules can
  /// reproduce it (`userId + ':' + foodId`) in the review_guards create rule.
  static String _compositeGuardId({
    required String userId,
    required String foodId,
  }) {
    return '$userId:$foodId';
  }

  /// Fetch a review by its deterministic composite key, regardless of
  /// `deleted` status — unlike [findExistingReview] which filters
  /// out soft-deleted documents.
  ///
  /// Returns `null` when no document exists for this composite key.
  Future<Review?> findByCompositeKey({
    required String userId,
    required String orderId,
    required String foodId,
  }) async {
    final docId = _compositeReviewId(
      userId: userId,
      orderId: orderId,
      foodId: foodId,
    );
    return getById(docId);
  }

  // ── Writes ─────────────────────────────────────────────────────────────────

  /// Create a new review document with atomic duplicate prevention.
  ///
  /// Uses a deterministic document ID derived from the composite key
  /// (userId, orderId, foodId) and a Firestore transaction to atomically
  /// enforce one review per combination — including soft-deleted reviews.
  ///
  /// Returns the new document ID on success, or `null` when a review
  /// already exists for the combination (duplicate).  Firestore
  /// permission, network, or write failures propagate to the caller so
  /// they are surfaced as errors rather than confused with duplicates.
  Future<String?> create(Map<String, dynamic> data) async {
    final foodId = data['foodId'] as String?;
    final orderId = data['orderId'] as String?;
    final userId = data['userId'] as String?;

    if (foodId == null || orderId == null || userId == null) {
      throw ArgumentError(
        '[ReviewRepository] create: missing composite key fields',
      );
    }

    final docId = _compositeReviewId(
      userId: userId,
      orderId: orderId,
      foodId: foodId,
    );
    final docRef = _firestore.collection(_collection).doc(docId);
    final guardRef = _firestore
        .collection(_guardCollection)
        .doc(_compositeGuardId(userId: userId, foodId: foodId));

    final alreadyExists = await _firestore.runTransaction<bool>((
      transaction,
    ) async {
      final doc = await transaction.get(docRef);
      if (doc.exists) {
        return true; // Already reviewed (including soft-deleted)
      }
      // One LIVE review per (user, food): the guard document exists whenever
      // a live review for this meal exists. Reading it inside this same
      // transaction makes the duplicate check atomic — two concurrent
      // creates for the same meal via different orders cannot both pass.
      final guard = await transaction.get(guardRef);
      if (guard.exists) {
        return true; // Another live review already exists for this meal
      }
      transaction.set(guardRef, {
        'userId': userId,
        'foodId': foodId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(docRef, data);
      return false; // Was created
    });

    return alreadyExists ? null : docId;
  }

  /// Revive a soft-deleted review, restoring the (user, food) guard
  /// atomically with the field update so the invariant "a live review
  /// implies a guard document" always holds. Without the guard, a
  /// concurrent create for the same meal via a different order could race
  /// past the duplicate check.
  ///
  /// Returns `false` when the review document does not exist.
  Future<bool> revive(String reviewId, Map<String, dynamic> data) async {
    final docRef = _firestore.collection(_collection).doc(reviewId);
    return _firestore.runTransaction<bool>((transaction) async {
      final doc = await transaction.get(docRef);
      if (!doc.exists) return false;
      transaction.update(docRef, data);
      final userId = doc.data()?['userId'] as String?;
      final foodId = doc.data()?['foodId'] as String?;
      if (userId != null && foodId != null) {
        transaction.set(
          _firestore
              .collection(_guardCollection)
              .doc(_compositeGuardId(userId: userId, foodId: foodId)),
          {
            'userId': userId,
            'foodId': foodId,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }
      return true;
    });
  }

  /// Update an existing review document.
  Future<bool> update(String reviewId, Map<String, dynamic> data) async {
    await _firestore.collection(_collection).doc(reviewId).update(data);
    return true;
  }

  /// Soft-delete a review by setting `deleted = true`.
  ///
  /// The (user, food) guard is deliberately NOT released here — that is
  /// server-controlled: the `onReviewChanged` Cloud Function deletes the
  /// guard when `deleted` becomes true, so a client can never release its
  /// own guard and create a duplicate live review for the same meal.
  Future<bool> softDelete(String reviewId) async {
    await _firestore.collection(_collection).doc(reviewId).update({
      'deleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }
}
