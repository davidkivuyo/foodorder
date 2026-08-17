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
import 'package:firebase_auth/firebase_auth.dart';
import '../models/review.dart';
import '../repositories/review_repository.dart';
import 'analytics_service.dart';
import 'app_log.dart';

/// Business-logic layer for the Reviews & Feedback system.
///
/// Responsibilities:
/// - Check review eligibility (collected orders containing the food item)
/// - Create, update, soft-delete reviews
/// - Incrementally update food rating statistics
/// - Provide review streams with pagination
///
/// Widgets must never manipulate Firestore directly.
class ReviewService {
  final ReviewRepository _repository;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ReviewService({
    ReviewRepository? repository,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _repository = repository ?? ReviewRepository(),
       _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  /// Current authenticated user ID, if any.
  ///
  /// Overridable in tests (FirebaseAuth itself cannot be subclassed).
  String? get currentUserId => _auth.currentUser?.uid;

  // ── Eligibility ────────────────────────────────────────────────────────────

  /// Check if the current user can review a food item.
  ///
  /// Once the user has reviewed this meal, edit mode is always preferred:
  /// the button must say "Edit Review" and never fall back to "Write a
  /// Review", even when the user has other collected (but unreviewed)
  /// orders of the same meal. The check is scoped per food item, so
  /// reviews for other meals never affect it.
  Future<ReviewEligibility> checkEligibility(String foodId) async {
    final userId = currentUserId;
    if (userId == null) {
      return ReviewEligibility.notEligible();
    }

    // 1. Find existing reviews for this food+user combination.
    final List<Review> existingReviews;
    try {
      existingReviews = await _repository.findUserReviewsForFood(
        foodId: foodId,
        userId: userId,
      );
    } on Exception catch (e) {
      AppLog.e('[ReviewService] checkEligibility review query error', e);
      return ReviewEligibility.notEligible();
    }

    // 2. A live review already exists for this meal — always edit mode.
    //    Soft-deleted reviews don't count: they are invisible and should
    //    allow a fresh review (createReview revives them by composite key).
    //
    //    The canonical review is selected deterministically: the most
    //    recently updated live review wins, with the document ID as a
    //    stable tiebreaker. createReview refuses to create a second live
    //    review for the same meal, so at most one canonical doc exists
    //    going forward — this ordering just makes legacy duplicates
    //    resolve the same way on every call.
    final liveReviews = existingReviews.where((r) => !r.deleted).toList();
    if (liveReviews.isNotEmpty) {
      // More than one live review for the same meal means legacy duplicate
      // data exists (created before the one-review-per-meal guard). Flag it
      // so the duplicates can be investigated and cleaned up; the sort below
      // still resolves a deterministic canonical review in the meantime.
      if (liveReviews.length > 1) {
        AppLog.w(
          '[ReviewService] checkEligibility: ${liveReviews.length} live '
          'reviews found for food $foodId — legacy duplicate data',
        );
      }
      liveReviews.sort((a, b) {
        final aTime =
            (a.updatedAt ?? a.createdAt) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            (b.updatedAt ?? b.createdAt) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final byTime = bTime.compareTo(aTime);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
      final canonical = liveReviews.first;
      return ReviewEligibility(
        eligible: true,
        hasExistingReview: true,
        existingReview: canonical,
        matchingOrderId: canonical.orderId,
      );
    }

    // 3. No live review yet — find a collected order containing this food
    //    item to attach the new review to.
    try {
      final orderIds = await _repository.findOrderIdsWithFoodItem(
        userId: userId,
        foodId: foodId,
      );
      for (final orderId in orderIds) {
        return ReviewEligibility(
          eligible: true,
          hasExistingReview: false,
          existingReview: null,
          matchingOrderId: orderId,
        );
      }
    } on Exception catch (e) {
      AppLog.e('[ReviewService] checkEligibility order query error', e);
      return ReviewEligibility.notEligible();
    }

    return ReviewEligibility.notEligible();
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

  /// Create a new review with atomic order eligibility enforcement.
  ///
  /// Verifies that:
  /// - The order belongs to the current user
  /// - The order has been collected
  /// - The order contains this food item
  /// - No review already exists for this (userId, orderId, foodId)
  ///
  /// Only creates the review with `verifiedPurchase: true` when all
  /// checks pass. Returns the review ID on success, or `null` on failure.
  Future<String?> createReview({
    required String foodId,
    required String orderId,
    required int rating,
    required List<String> templateTags,
    String comment = '',
    bool anonymous = true,
    String? displayName,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;

    // ── Step 0: One live review per (user, food) — reject duplicates ──
    // A user may only have a single live review for a given meal, no
    // matter which collected order it is attached to. Without this guard,
    // a second review for the same meal via a different order would
    // inflate the food's reviewCount and rating distribution. Soft-deleted
    // reviews don't block: they are invisible and may be revived or
    // replaced.
    try {
      final existingReviews = await _repository.findUserReviewsForFood(
        foodId: foodId,
        userId: userId,
      );
      if (existingReviews.any((r) => !r.deleted)) {
        AppLog.d(
          '[ReviewService] createReview: user already has a live review for food $foodId',
        );
        return null;
      }
    } on Exception catch (e) {
      AppLog.e('[ReviewService] createReview duplicate guard error', e);
      return null;
    }

    // ── Step 1: Verify order eligibility atomically ──────────────────
    try {
      final orderDoc = await _firestore.collection('orders').doc(orderId).get();

      if (!orderDoc.exists) {
        AppLog.d('[ReviewService] createReview: order $orderId not found');
        return null;
      }

      final orderData = orderDoc.data()!;

      // Check ownership
      if (orderData['studentId'] != userId) {
        AppLog.d(
          '[ReviewService] createReview: order $orderId ownership mismatch — rejected',
        );
        return null;
      }

      // Check order is collected (case-insensitive to handle
      // any normalized casing in the stored status).
      final status = orderData['status'] as String? ?? '';
      if (status.toLowerCase() != 'collected') {
        AppLog.d(
          '[ReviewService] createReview: order $orderId status is $status, not collected',
        );
        return null;
      }

      // Check order contains this food item
      final items = orderData['items'];
      bool containsFood = false;
      if (items is List) {
        for (final item in items) {
          if (item is Map) {
            final itemFoodId =
                item['foodItemId'] as String? ?? item['id'] as String? ?? '';
            if (itemFoodId == foodId) {
              containsFood = true;
              break;
            }
          }
        }
      }
      if (!containsFood) {
        AppLog.d(
          '[ReviewService] createReview: order $orderId does not contain food $foodId',
        );
        return null;
      }
    } on Exception catch (e) {
      AppLog.e('[ReviewService] createReview eligibility check error', e);
      return null;
    }

    // ── Step 2: Validate input ───────────────────────────────────────
    final clampedRating = rating.clamp(1, 5);
    final sanitizedComment = _sanitizeComment(comment);
    if (sanitizedComment == null) {
      AppLog.d('[ReviewService] createReview: comment rejected');
      return null;
    }
    final validTags = _validateTags(templateTags);
    final currentUserDisplayName = _auth.currentUser?.displayName;
    final name = anonymous
        ? 'CampusBite Customer'
        : ((displayName != null && displayName.isNotEmpty)
              ? displayName
              : (currentUserDisplayName != null &&
                    currentUserDisplayName.isNotEmpty)
              ? currentUserDisplayName
              : 'CampusBite Customer');

    // ── Step 3: Create or revive the review ──────────────────────────
    final review = Review(
      foodId: foodId,
      orderId: orderId,
      userId: userId,
      displayName: name,
      anonymous: anonymous,
      rating: clampedRating,
      templateTags: validTags,
      comment: sanitizedComment,
      verifiedPurchase: true,
    );

    try {
      // Check if a soft-deleted review exists for this composite key.
      final softDeleted = await _repository.findByCompositeKey(
        userId: userId,
        orderId: orderId,
        foodId: foodId,
      );

      if (softDeleted != null && softDeleted.deleted) {
        // Revive the soft-deleted review. We must write ONLY the fields
        // that validReviewUpdate() allows — sending immutable fields
        // (foodId, orderId, userId, verifiedPurchase) causes a
        // Firestore permission-denied error because they are not in the
        // allowed update set.
        final reviveData = <String, dynamic>{
          'rating': review.rating,
          'templateTags': review.templateTags,
          'comment': review.comment,
          'anonymous': review.anonymous,
          'displayName': review.displayName,
          'deleted': false,
          'deletedAt': null,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        final revived = await _repository.revive(softDeleted.id, reviveData);
        // Rating stats are updated server-side by the onReviewChanged
        // Cloud Function. No client-side aggregation needed.
        if (revived) {
          AnalyticsService.instance.logEvent(AnalyticsEvent.reviewSubmitted);
        }
        return revived ? softDeleted.id : null;
      }

      // No existing document — create a new one.
      final docId = await _repository.create(review.toFirestore());
      // Rating stats are updated server-side by the onReviewChanged
      // Cloud Function. No client-side aggregation needed.
      if (docId != null) {
        AnalyticsService.instance.logEvent(AnalyticsEvent.reviewSubmitted);
      }
      return docId;
    } on Exception catch (e) {
      AppLog.e('[ReviewService] createReview write error', e);
      return null;
    }
  }

  /// Update an existing review and refresh food rating statistics.
  ///
  /// Verifies the review belongs to the current user before mutating.
  Future<bool> updateReview({
    required String reviewId,
    required String foodId,
    required int rating,
    required List<String> templateTags,
    String comment = '',
    bool anonymous = true,
    String? displayName,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;

    // ── Ownership & foodId check ─────────────────────────────────────
    final existing = await _repository.getById(reviewId);
    if (existing == null) {
      AppLog.d('[ReviewService] updateReview: review $reviewId not found');
      return false;
    }
    if (existing.userId != userId) {
      AppLog.d(
        '[ReviewService] updateReview: review $reviewId owned by another user — rejected',
      );
      return false;
    }
    if (existing.foodId != foodId) {
      AppLog.d(
        '[ReviewService] updateReview: review $reviewId foodId mismatch — rejected',
      );
      return false;
    }

    // Validate rating range
    final clampedRating = rating.clamp(1, 5);

    // Validate comment
    final sanitizedComment = _sanitizeComment(comment);
    if (sanitizedComment == null) {
      AppLog.d('[ReviewService] updateReview: comment rejected');
      return false;
    }

    // Validate template tags (predefined set, max 5)
    final validTags = _validateTags(templateTags);

    // Determine display name
    final currentUserDisplayName = _auth.currentUser?.displayName;
    final name = anonymous
        ? 'CampusBite Customer'
        : ((displayName != null && displayName.isNotEmpty)
              ? displayName
              : (currentUserDisplayName != null &&
                    currentUserDisplayName.isNotEmpty)
              ? currentUserDisplayName
              : 'CampusBite Customer');

    final success = await _repository.update(reviewId, {
      'rating': clampedRating,
      'templateTags': validTags,
      'comment': sanitizedComment,
      'anonymous': anonymous,
      'displayName': name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Rating stats are updated server-side by the onReviewChanged
    // Cloud Function. No client-side aggregation needed.
    return success;
  }

  /// Soft-delete a review and refresh food rating statistics.
  ///
  /// Verifies the review belongs to the current user before mutating.
  Future<bool> deleteReview({
    required String reviewId,
    required String foodId,
  }) async {
    final userId = currentUserId;
    if (userId == null) return false;

    // ── Ownership & foodId check ─────────────────────────────────────
    final existing = await _repository.getById(reviewId);
    if (existing == null) {
      AppLog.d('[ReviewService] deleteReview: review $reviewId not found');
      return false;
    }
    if (existing.userId != userId) {
      AppLog.d(
        '[ReviewService] deleteReview: review $reviewId owned by another user — rejected',
      );
      return false;
    }
    if (existing.foodId != foodId) {
      AppLog.d(
        '[ReviewService] deleteReview: review $reviewId foodId mismatch — rejected',
      );
      return false;
    }

    final success = await _repository.softDelete(reviewId);
    // Rating stats are updated server-side by the onReviewChanged
    // Cloud Function. No client-side aggregation needed.
    return success;
  }

  // ── Streaming / Pagination ─────────────────────────────────────────────────

  /// Stream of non-deleted reviews for a food item, paginated.
  Stream<List<Review>> foodReviewsStream({
    required String foodId,
    int limit = 20,
    DocumentSnapshot? lastDoc,
    String orderBy = 'createdAt',
    bool descending = true,
  }) {
    return _repository.foodReviewsStream(
      foodId: foodId,
      limit: limit,
      lastDoc: lastDoc,
      orderBy: orderBy,
      descending: descending,
    );
  }

  /// One-shot fetch of reviews with pagination support.
  Future<MapEntry<List<Review>, DocumentSnapshot?>> fetchFoodReviews({
    required String foodId,
    int limit = 20,
    DocumentSnapshot? lastDoc,
    String orderBy = 'createdAt',
    bool descending = true,
  }) async {
    return _repository.fetchFoodReviews(
      foodId: foodId,
      limit: limit,
      lastDoc: lastDoc,
      orderBy: orderBy,
      descending: descending,
    );
  }

  /// Watch a food item's document for live rating-stat updates.
  ///
  /// Returns a stream of [DocumentSnapshot] that emits whenever the
  /// food item document changes (e.g. after a review is created, edited,
  /// or deleted and the onReviewChanged Cloud Function updates the stats).
  Stream<DocumentSnapshot> watchFoodStats(String foodId) {
    return _firestore.collection('food_items').doc(foodId).snapshots();
  }

  /// Compute rating distribution as percentages (0–100) for the dashboard.
  ///
  /// Rating stats are now maintained server-side by the onReviewChanged
  /// Cloud Function. This helper is used only for display in the UI.
  static Map<String, double> distributionPercentages(
    Map<String, dynamic>? distribution,
    int totalCount,
  ) {
    if (distribution == null || totalCount == 0) {
      return {'1': 0.0, '2': 0.0, '3': 0.0, '4': 0.0, '5': 0.0};
    }

    return {
      for (final entry in distribution.entries)
        entry.key:
            ((entry.value as num?)?.toDouble() ?? 0.0) / totalCount * 100,
    };
  }

  // ── Comment Validation ─────────────────────────────────────────────────────

  /// Sanitize and validate a review comment.
  ///
  /// - Trim whitespace
  /// - Reject if contains URLs (requires explicit http:// or https:// scheme)
  /// - Reject if contains HTML tags
  /// - Reject if contains profanity (basic filter)
  /// - Truncate to 120 characters
  ///
  /// Returns the sanitized comment on success, or `null` on rejection.
  String? _sanitizeComment(String comment) {
    String sanitized = comment.trim();

    // Reject if contains URLs (scheme is now required — avoids false
    // positives like "e.g." or "9.5/10").
    if (_containsUrl(sanitized)) return null;

    // Reject if contains HTML tags
    if (_containsHtml(sanitized)) return null;

    // Basic profanity filter
    if (_containsProfanity(sanitized)) return null;

    // Truncate to 120 characters
    if (sanitized.length > 120) {
      sanitized = sanitized.substring(0, 120);
    }

    return sanitized;
  }

  /// Detect URLs in comment text, including bare domains and
  /// www-prefixed links in addition to explicit http/https schemes.
  ///
  /// Avoids false positives on ordinary dotted tokens such as "e.g.",
  /// "i.e.", or "9.5/10" by requiring:
  /// - Domain names to start with a letter (excludes "9.5/10")
  /// - TLD segments to be at least 2 alpha characters (excludes "e.g.")
  ///
  /// Catches examples like foodpromo.com/deal and www.spamsite.net.
  bool _containsUrl(String text) {
    final urlPattern = RegExp(
      r'(?:https?://\S+|www\.[a-zA-Z][a-zA-Z0-9-]*\.[a-zA-Z]{2,}(?:/\S*)?|\b[a-zA-Z][a-zA-Z0-9-]*\.(?:com|net|org|io|co|app|dev)\b(?:/\S*)?)',
      caseSensitive: false,
    );
    return urlPattern.hasMatch(text);
  }

  bool _containsHtml(String text) {
    final htmlPattern = RegExp(r'<[^>]*>');
    return htmlPattern.hasMatch(text);
  }

  bool _containsProfanity(String text) {
    // Basic profanity filter — can be extended.
    final profanityPattern = RegExp(
      r'\b(fuck|shit|ass|bitch|damn|crap|dick|piss|slut|bastard)\b',
      caseSensitive: false,
    );
    return profanityPattern.hasMatch(text);
  }

  // ── Tag Validation ─────────────────────────────────────────────────────────

  /// Validate review template tags against the predefined set.
  ///
  /// Filters the input to only include tags from [reviewTemplateTags],
  /// deduplicates while preserving input order, and retains at most
  /// five entries. Repeated allowed tags occupy only one slot.
  List<String> _validateTags(List<String> tags) {
    final allowed = reviewTemplateTags.toSet();
    final seen = <String>{};
    final result = <String>[];
    for (final tag in tags) {
      if (!allowed.contains(tag)) continue;
      if (seen.contains(tag)) continue;
      seen.add(tag);
      result.add(tag);
      if (result.length >= 5) break;
    }
    return result;
  }
}

/// Describes whether a user can review a particular food item.
class ReviewEligibility {
  final bool eligible;
  final bool hasExistingReview;
  final Review? existingReview;
  final String? matchingOrderId;

  const ReviewEligibility({
    required this.eligible,
    required this.hasExistingReview,
    this.existingReview,
    this.matchingOrderId,
  });

  factory ReviewEligibility.notEligible() {
    return const ReviewEligibility(
      eligible: false,
      hasExistingReview: false,
      existingReview: null,
      matchingOrderId: null,
    );
  }
}
