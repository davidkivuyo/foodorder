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

import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/models/review.dart';
import 'package:campusbite/repositories/review_repository.dart';
import 'package:campusbite/services/review_service.dart';

import 'firebase_test_helper.dart';

/// [ReviewRepository] with scriptable per-food/per-user review and order
/// lookups, mirroring the real repository's scoping:
///
/// - [findUserReviewsForFood] filters by (foodId, userId).
/// - [findOrderIdsWithFoodItem] filters by (foodId, userId) via the keyed
///   [collectedOrders] map, so queries for different meals or users can
///   never return unrelated order IDs.
class _FakeReviewRepository extends ReviewRepository {
  _FakeReviewRepository({
    required this.reviews,
    required this.collectedOrders,
  });

  final List<Review> reviews;

  /// Collected order IDs keyed by `(userId, foodId)`.
  final Map<(String, String), List<String>> collectedOrders;

  @override
  Future<List<Review>> findUserReviewsForFood({
    required String foodId,
    required String userId,
  }) async {
    return reviews
        .where((r) => r.foodId == foodId && r.userId == userId)
        .toList();
  }

  @override
  Future<List<String>> findOrderIdsWithFoodItem({
    required String userId,
    required String foodId,
  }) async {
    return List.unmodifiable(
      collectedOrders[(userId, foodId)] ?? const <String>[],
    );
  }
}

/// [ReviewService] with a fixed authenticated user ID so eligibility can be
/// tested without a real FirebaseAuth session.
class _TestReviewService extends ReviewService {
  _TestReviewService({
    required ReviewRepository repository,
    required this.uid,
  }) : super(repository: repository);

  final String? uid;

  @override
  String? get currentUserId => uid;
}

Review _review({
  String id = 'r1',
  String foodId = 'food_a',
  String orderId = 'order_1',
  String userId = 'user_1',
  bool deleted = false,
}) {
  return Review(
    id: id,
    foodId: foodId,
    orderId: orderId,
    userId: userId,
    rating: 5,
    deleted: deleted,
  );
}

void main() {
  setUpAll(setupFirebaseForTest);

  group('ReviewService.checkEligibility — button consistency', () {
    test('returns not eligible when the user is signed out', () async {
      final service = _TestReviewService(
        repository: _FakeReviewRepository(
          reviews: const [],
          collectedOrders: const {('user_1', 'food_a'): ['order_1']},
        ),
        uid: null,
      );

      final result = await service.checkEligibility('food_a');

      expect(result.eligible, isFalse);
      expect(result.hasExistingReview, isFalse);
    });

    test('returns not eligible with no review and no collected order',
        () async {
      final service = _TestReviewService(
        repository: _FakeReviewRepository(
          reviews: const [],
          collectedOrders: const {},
        ),
        uid: 'user_1',
      );

      final result = await service.checkEligibility('food_a');

      expect(result.eligible, isFalse);
      expect(result.hasExistingReview, isFalse);
    });

    test('orders belonging to another user do not grant eligibility',
        () async {
      final service = _TestReviewService(
        repository: _FakeReviewRepository(
          reviews: const [],
          collectedOrders: const {('user_9', 'food_a'): ['order_x']},
        ),
        uid: 'user_1',
      );

      final result = await service.checkEligibility('food_a');

      expect(result.eligible, isFalse);
      expect(result.hasExistingReview, isFalse);
    });

    test('first-time review with a collected order offers Write mode',
        () async {
      final service = _TestReviewService(
        repository: _FakeReviewRepository(
          reviews: const [],
          collectedOrders: const {('user_1', 'food_a'): ['order_1']},
        ),
        uid: 'user_1',
      );

      final result = await service.checkEligibility('food_a');

      expect(result.eligible, isTrue);
      expect(result.hasExistingReview, isFalse);
      expect(result.existingReview, isNull);
      expect(result.matchingOrderId, 'order_1');
    });

    test('a live review always offers Edit mode', () async {
      final service = _TestReviewService(
        repository: _FakeReviewRepository(
          reviews: [_review(id: 'r1', orderId: 'order_1')],
          collectedOrders: const {('user_1', 'food_a'): ['order_1']},
        ),
        uid: 'user_1',
      );

      final result = await service.checkEligibility('food_a');

      expect(result.eligible, isTrue);
      expect(result.hasExistingReview, isTrue);
      expect(result.existingReview?.id, 'r1');
      expect(result.matchingOrderId, 'order_1');
    });

    test('a live review stays Edit mode even with a newer unreviewed order '
        'of the same meal', () async {
      final service = _TestReviewService(
        repository: _FakeReviewRepository(
          reviews: [_review(id: 'r1', orderId: 'order_1')],
          collectedOrders: const {
            ('user_1', 'food_a'): ['order_1', 'order_2'],
          },
        ),
        uid: 'user_1',
      );

      final result = await service.checkEligibility('food_a');

      // The user already reviewed this meal — the button must say
      // "Edit Review", never "Write a Review", regardless of the newer
      // collected (but unreviewed) order of the same meal.
      expect(result.eligible, isTrue);
      expect(result.hasExistingReview, isTrue);
      expect(result.existingReview?.id, 'r1');
      expect(result.matchingOrderId, 'order_1');
    });

    test('reviews and orders of other meals never turn this meal into '
        'Edit mode', () async {
      final service = _TestReviewService(
        repository: _FakeReviewRepository(
          reviews: [_review(id: 'r1', foodId: 'food_a', orderId: 'order_1')],
          collectedOrders: const {
            ('user_1', 'food_a'): ['order_1'],
            ('user_1', 'food_b'): ['order_2'],
          },
        ),
        uid: 'user_1',
      );

      // Meal B: the user has never reviewed it, but has a collected order.
      final resultB = await service.checkEligibility('food_b');

      expect(resultB.eligible, isTrue);
      expect(resultB.hasExistingReview, isFalse);
      expect(resultB.matchingOrderId, 'order_2');

      // Meal A: the user HAS reviewed it.
      final resultA = await service.checkEligibility('food_a');

      expect(resultA.eligible, isTrue);
      expect(resultA.hasExistingReview, isTrue);
      expect(resultA.existingReview?.id, 'r1');
    });

    test('a soft-deleted review does not force Edit mode', () async {
      final service = _TestReviewService(
        repository: _FakeReviewRepository(
          reviews: [_review(id: 'r1', orderId: 'order_1', deleted: true)],
          collectedOrders: const {('user_1', 'food_a'): ['order_1']},
        ),
        uid: 'user_1',
      );

      final result = await service.checkEligibility('food_a');

      // The deleted review is invisible — the user may write a fresh
      // review (createReview revives the soft-deleted document).
      expect(result.eligible, isTrue);
      expect(result.hasExistingReview, isFalse);
      expect(result.matchingOrderId, 'order_1');
    });

    test('multiple live reviews for the same meal still offer Edit mode',
        () async {
      final service = _TestReviewService(
        repository: _FakeReviewRepository(
          reviews: [
            _review(id: 'r1', orderId: 'order_1'),
            _review(id: 'r2', orderId: 'order_2'),
          ],
          collectedOrders: const {
            ('user_1', 'food_a'): ['order_1', 'order_2'],
          },
        ),
        uid: 'user_1',
      );

      final result = await service.checkEligibility('food_a');

      expect(result.eligible, isTrue);
      expect(result.hasExistingReview, isTrue);
      expect(result.existingReview, isNotNull);
      expect(result.matchingOrderId, isNotNull);
    });
  });
}
