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
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campusbite/models/review.dart';
import 'package:campusbite/repositories/review_repository.dart';
import 'package:campusbite/services/review_service.dart';

import 'firebase_test_helper.dart';

/// [ReviewRepository] backed by a [FakeFirebaseFirestore] for the
/// repository's own writes ([create], [findByCompositeKey]) and with a
/// scriptable per-(user, food) review list for the duplicate guard.
class _FakeReviewRepository extends ReviewRepository {
  _FakeReviewRepository({
    required FirebaseFirestore firestore,
    required this.reviews,
  }) : super(firestore: firestore);

  final List<Review> reviews;

  @override
  Future<List<Review>> findUserReviewsForFood({
    required String foodId,
    required String userId,
  }) async {
    return reviews
        .where((r) => r.foodId == foodId && r.userId == userId)
        .toList();
  }
}

/// [ReviewService] with a fixed authenticated user ID and an injectable
/// Firestore so `createReview`'s order read hits the fake database.
class _TestReviewService extends ReviewService {
  _TestReviewService({
    required super.repository,
    required super.firestore,
    required this.uid,
  });

  final String? uid;

  @override
  String? get currentUserId => uid;
}

Review _review({
  String id = 'user_1:order_1:food_a',
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

/// Seed a valid COLLECTED order for [userId] containing [foodId].
Future<void> _seedCollectedOrder(
  FakeFirebaseFirestore firestore, {
  required String orderId,
  required String userId,
  required String foodId,
}) async {
  await firestore.collection('orders').doc(orderId).set({
    'studentId': userId,
    'status': 'collected',
    'items': [
      {'foodItemId': foodId},
    ],
  });
}

void main() {
  setUpAll(setupFirebaseForTest);

  group('ReviewService.createReview — one live review per (user, food)', () {
    test(
      'refuses a second live review for the same meal via a different order',
      () async {
        final firestore = FakeFirebaseFirestore();
        await _seedCollectedOrder(
          firestore,
          orderId: 'order_2',
          userId: 'user_1',
          foodId: 'food_a',
        );
        final repository = _FakeReviewRepository(
          firestore: firestore,
          reviews: [_review(id: 'user_1:order_1:food_a', orderId: 'order_1')],
        );
        final service = _TestReviewService(
          repository: repository,
          firestore: firestore,
          uid: 'user_1',
        );

        // The user already reviewed this meal via order_1 — creating a review
        // through order_2 must be refused so reviewCount/distribution are not
        // inflated by a duplicate live review.
        final docId = await service.createReview(
          foodId: 'food_a',
          orderId: 'order_2',
          rating: 4,
          templateTags: const [],
        );

        expect(docId, isNull);
        final written = await firestore.collection('reviews').get();
        expect(
          written.docs,
          isEmpty,
          reason: 'No review document may be created for the duplicate',
        );
      },
    );

    test(
      'refuses a duplicate even when the order matches the existing review',
      () async {
        final firestore = FakeFirebaseFirestore();
        await _seedCollectedOrder(
          firestore,
          orderId: 'order_1',
          userId: 'user_1',
          foodId: 'food_a',
        );
        final repository = _FakeReviewRepository(
          firestore: firestore,
          reviews: [_review(id: 'user_1:order_1:food_a', orderId: 'order_1')],
        );
        final service = _TestReviewService(
          repository: repository,
          firestore: firestore,
          uid: 'user_1',
        );

        final docId = await service.createReview(
          foodId: 'food_a',
          orderId: 'order_1',
          rating: 3,
          templateTags: const [],
        );

        expect(docId, isNull);
      },
    );

    test('reviews belonging to another user never block this user', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedCollectedOrder(
        firestore,
        orderId: 'order_2',
        userId: 'user_1',
        foodId: 'food_a',
      );
      final repository = _FakeReviewRepository(
        firestore: firestore,
        reviews: [
          _review(
            id: 'user_9:order_1:food_a',
            orderId: 'order_1',
            userId: 'user_9',
          ),
        ],
      );
      final service = _TestReviewService(
        repository: repository,
        firestore: firestore,
        uid: 'user_1',
      );

      final docId = await service.createReview(
        foodId: 'food_a',
        orderId: 'order_2',
        rating: 4,
        templateTags: const [],
      );

      expect(docId, 'user_1:order_2:food_a');
      final doc = await firestore
          .collection('reviews')
          .doc('user_1:order_2:food_a')
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['rating'], 4);
    });

    test(
      'a soft-deleted review does not block — the document is revived',
      () async {
        final firestore = FakeFirebaseFirestore();
        await _seedCollectedOrder(
          firestore,
          orderId: 'order_1',
          userId: 'user_1',
          foodId: 'food_a',
        );
        // The soft-deleted document must exist in Firestore for the revive
        // path (findByCompositeKey) to find it.
        await firestore.collection('reviews').doc('user_1:order_1:food_a').set({
          'foodId': 'food_a',
          'orderId': 'order_1',
          'userId': 'user_1',
          'displayName': 'CampusBite Customer',
          'anonymous': true,
          'rating': 2,
          'templateTags': <String>[],
          'comment': '',
          'deleted': true,
          'deletedAt': null,
          'verifiedPurchase': true,
        });
        final repository = _FakeReviewRepository(
          firestore: firestore,
          reviews: [
            _review(
              id: 'user_1:order_1:food_a',
              orderId: 'order_1',
              deleted: true,
            ),
          ],
        );
        final service = _TestReviewService(
          repository: repository,
          firestore: firestore,
          uid: 'user_1',
        );

        final docId = await service.createReview(
          foodId: 'food_a',
          orderId: 'order_1',
          rating: 4,
          templateTags: const [],
        );

        expect(docId, 'user_1:order_1:food_a');
        final doc = await firestore
            .collection('reviews')
            .doc('user_1:order_1:food_a')
            .get();
        expect(doc.exists, isTrue);
        expect(doc.data()?['deleted'], isFalse);
        expect(doc.data()?['rating'], 4);
      },
    );

    test(
      'creates a fresh review when the user has never reviewed the meal',
      () async {
        final firestore = FakeFirebaseFirestore();
        await _seedCollectedOrder(
          firestore,
          orderId: 'order_2',
          userId: 'user_1',
          foodId: 'food_a',
        );
        final repository = _FakeReviewRepository(
          firestore: firestore,
          reviews: const [],
        );
        final service = _TestReviewService(
          repository: repository,
          firestore: firestore,
          uid: 'user_1',
        );

        final docId = await service.createReview(
          foodId: 'food_a',
          orderId: 'order_2',
          rating: 5,
          templateTags: const ['Great deal'],
        );

        expect(docId, 'user_1:order_2:food_a');
        final doc = await firestore
            .collection('reviews')
            .doc('user_1:order_2:food_a')
            .get();
        expect(doc.exists, isTrue);
        expect(doc.data()?['rating'], 5);
        expect(doc.data()?['deleted'], isFalse);
      },
    );

    test('returns null when the user is signed out', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = _FakeReviewRepository(
        firestore: firestore,
        reviews: const [],
      );
      final service = _TestReviewService(
        repository: repository,
        firestore: firestore,
        uid: null,
      );

      final docId = await service.createReview(
        foodId: 'food_a',
        orderId: 'order_1',
        rating: 4,
        templateTags: const [],
      );

      expect(docId, isNull);
    });
  });

  group(
    'ReviewRepository — transactional one-live-review-per-(user, food) guard',
    () {
      Map<String, dynamic> reviewData({
        required String orderId,
        required int rating,
      }) {
        return {
          'userId': 'user_1',
          'orderId': orderId,
          'foodId': 'food_a',
          'rating': rating,
          'deleted': false,
        };
      }

      test(
        'create refuses a second live review via a different order (guard)',
        () async {
          final firestore = FakeFirebaseFirestore();
          final repository = _FakeReviewRepository(
            firestore: firestore,
            reviews: const [],
          );
          // Bypass the service-level pre-check entirely: write the first
          // review directly through the repository, then attempt a second
          // for the same meal via a different order.
          final firstId = await repository.create(
            reviewData(orderId: 'order_1', rating: 5),
          );
          expect(firstId, 'user_1:order_1:food_a');

          final secondId = await repository.create(
            reviewData(orderId: 'order_2', rating: 4),
          );
          expect(
            secondId,
            isNull,
            reason: 'the (user, food) guard must block the duplicate create',
          );
          final written = await firestore.collection('reviews').get();
          expect(written.docs.length, 1);
          final guard = await firestore
              .collection('review_guards')
              .doc('user_1:food_a')
              .get();
          expect(guard.exists, isTrue, reason: 'guard claimed with the review');
        },
      );

      test(
        'soft-deleting the review releases the guard so a fresh review is allowed',
        () async {
          final firestore = FakeFirebaseFirestore();
          final repository = _FakeReviewRepository(
            firestore: firestore,
            reviews: const [],
          );
          await repository.create(
            reviewData(orderId: 'order_1', rating: 5),
          );

          await repository.softDelete('user_1:order_1:food_a');

          final secondId = await repository.create(
            reviewData(orderId: 'order_2', rating: 4),
          );
          expect(secondId, 'user_1:order_2:food_a');
          final guard = await firestore
              .collection('review_guards')
              .doc('user_1:food_a')
              .get();
          expect(
            guard.exists,
            isTrue,
            reason: 'guard re-claimed by the new live review',
          );
        },
      );

      test('reviving a soft-deleted review restores the guard atomically',
          () async {
        final firestore = FakeFirebaseFirestore();
        final repository = _FakeReviewRepository(
          firestore: firestore,
          reviews: const [],
        );
        await firestore.collection('reviews').doc('user_1:order_1:food_a').set({
          'userId': 'user_1',
          'orderId': 'order_1',
          'foodId': 'food_a',
          'rating': 2,
          'deleted': true,
        });

        final revived = await repository.revive(
          'user_1:order_1:food_a',
          {'deleted': false, 'rating': 4},
        );
        expect(revived, isTrue);
        final guard = await firestore
            .collection('review_guards')
            .doc('user_1:food_a')
            .get();
        expect(
          guard.exists,
          isTrue,
          reason: 'revive must restore the guard with the live review',
        );

        // The restored guard now blocks a duplicate for the same meal via
        // another order, even without any service-level query.
        final secondId = await repository.create(
          reviewData(orderId: 'order_2', rating: 4),
        );
        expect(secondId, isNull);
      });
    },
  );
}
