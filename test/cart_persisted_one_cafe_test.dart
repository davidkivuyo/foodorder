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
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:campusbite/data/food_data.dart';
import 'package:campusbite/models/sync_operation.dart';
import 'package:campusbite/services/cart_service.dart';
import 'package:campusbite/services/connectivity_service.dart';

/// A manually created FoodItem for test scenarios.
FoodItem _testItem({
  String id = 'food_001',
  String title = 'Test Item',
  List<String> availableCafes = const ['Cafe A'],
}) {
  return FoodItem(
    id: id,
    image: 'https://example.com/img.jpg',
    title: title,
    titleLower: title.toLowerCase(),
    subtitle: 'Test subtitle',
    description: 'Test description',
    price: 5000,
    rating: 4.0,
    category: 'Test',
    availableCafes: availableCafes,
    time: '10 min',
    section: 'test',
    available: true,
    quantity: 99,
  );
}

void main() {
  group('CartService — one cafe per order against the PERSISTED cart', () {
    late FakeFirebaseFirestore fakeFirestore;
    late CartService cartService;
    const userId = 'user_123';
    const lockDocId = '_cart_lock_';

    setUp(() {
      // Online path: the singleton connectivity state requires the widget
      // binding in plain test(), so use the testable mock (initialOnline true).
      ConnectivityService.setMockInstance(
        ConnectivityService.testing(initialOnline: true),
      );
      fakeFirestore = FakeFirebaseFirestore();
      cartService = CartService.testing(
        firestore: fakeFirestore,
        userId: userId,
      );
    });

    Future<List<dynamic>> cartItemDocs() async {
      final snapshot = await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('cart')
          .get();
      return snapshot.docs
          .where((d) => d.data()['foodItemId'] != null)
          .toList();
    }

    Future<void> seedCartItem(String id, String cafe) async {
      await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('cart')
          .doc('${id}_$cafe')
          .set({
        'foodItemId': id,
        'quantity': 1,
        'selectedCafe': cafe,
      });
    }

    test('online add refuses when the persisted cart holds a different cafe',
        () async {
      await seedCartItem('food_a', 'Cafe A');
      final itemB = _testItem(id: 'food_b', availableCafes: const ['Cafe B']);

      final success = await cartService.addToCart(
        itemB,
        selectedCafe: 'Cafe B',
      );
      expect(success, isFalse,
          reason: 'mixing cafes against persisted state must be refused');

      final docs = await cartItemDocs();
      expect(docs.length, 1, reason: 'no Cafe B item may be persisted');
      expect(docs.first.data()['selectedCafe'], 'Cafe A');
    });

    test('online add succeeds when the persisted cart holds the same cafe',
        () async {
      await seedCartItem('food_a', 'Cafe A');
      final itemB = _testItem(id: 'food_b', availableCafes: const ['Cafe A']);

      final success = await cartService.addToCart(
        itemB,
        selectedCafe: 'Cafe A',
      );
      expect(success, isTrue);

      final docs = await cartItemDocs();
      expect(docs.length, 2, reason: 'both Cafe A items are persisted');
    });

    test('online add on an empty cart succeeds and writes the lock doc',
        () async {
      final item = _testItem(id: 'food_a', availableCafes: const ['Cafe A']);

      final success = await cartService.addToCart(
        item,
        selectedCafe: 'Cafe A',
      );
      expect(success, isTrue);

      final snapshot = await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('cart')
          .get();
      // The composite item plus the serialization lock document.
      expect(snapshot.docs.length, 2);
      expect(snapshot.docs.any((d) => d.id == lockDocId), isTrue);
      expect(await cartItemDocs(), hasLength(1));
    });

    test('handleCartAddOp drops a queued op whose cafe conflicts with the '
        'persisted cart', () async {
      await seedCartItem('food_a', 'Cafe A');
      final itemB = _testItem(id: 'food_b', availableCafes: const ['Cafe B']);
      await fakeFirestore
          .collection('food_items')
          .doc(itemB.id)
          .set(itemB.toMap());

      final op = SyncOperation(
        id: 'op-conflict',
        type: 'cart_add',
        ownerUserId: userId,
        payload: {
          'foodItemId': itemB.id,
          'quantity': 1,
          'selectedCafe': 'Cafe B',
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final success = await cartService.handleCartAddOp(op);
      expect(success, isTrue,
          reason: 'a stale conflicting op is dropped, not retried');

      final docs = await cartItemDocs();
      expect(docs.length, 1, reason: 'no Cafe B item may be persisted');
      expect(docs.first.data()['selectedCafe'], 'Cafe A');
    });

    test('handleCartAddOp applies a queued op matching the persisted cart cafe',
        () async {
      await seedCartItem('food_a', 'Cafe A');
      final itemB = _testItem(id: 'food_b', availableCafes: const ['Cafe A']);
      await fakeFirestore
          .collection('food_items')
          .doc(itemB.id)
          .set(itemB.toMap());

      final op = SyncOperation(
        id: 'op-ok',
        type: 'cart_add',
        ownerUserId: userId,
        payload: {
          'foodItemId': itemB.id,
          'quantity': 1,
          'selectedCafe': 'Cafe A',
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final success = await cartService.handleCartAddOp(op);
      expect(success, isTrue);

      final docs = await cartItemDocs();
      expect(docs.length, 2);
    });

    test('cafeless item conflicts with a persisted cafe item', () async {
      await seedCartItem('food_a', 'Cafe A');
      final offCampus = _testItem(id: 'food_off', availableCafes: const []);

      final success = await cartService.addToCart(offCampus);
      expect(success, isFalse);
      expect(await cartItemDocs(), hasLength(1));
    });

    test('add is rejected when the lock marker holds a different cafe '
        '(concurrent add committed after the outer read)', () async {
      // Simulate a different-cafe add whose transaction committed between the
      // outer query snapshot and this add's transaction: seed only the lock
      // marker (no item docs visible to the outer query).
      await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('cart')
          .doc(lockDocId)
          .set({'cafe': 'Cafe A', 'lockedAt': DateTime.now()});
      final itemB = _testItem(id: 'food_b', availableCafes: const ['Cafe B']);

      final success = await cartService.addToCart(
        itemB,
        selectedCafe: 'Cafe B',
      );
      expect(success, isFalse,
          reason: 'the transaction-fresh lock marker must block the add');
      expect(await cartItemDocs(), isEmpty,
          reason: 'no Cafe B item may be persisted');
    });

    test('clearing the cart removes the lock marker so a different cafe '
        'can be added afterwards', () async {
      final itemA = _testItem(id: 'food_a', availableCafes: const ['Cafe A']);
      expect(
        await cartService.addToCart(itemA, selectedCafe: 'Cafe A'),
        isTrue,
      );

      await cartService.clearCart();

      final itemB = _testItem(id: 'food_b', availableCafes: const ['Cafe B']);
      final success = await cartService.addToCart(
        itemB,
        selectedCafe: 'Cafe B',
      );
      expect(success, isTrue,
          reason: 'the lock marker must be gone after clearing the cart');
      expect((await cartItemDocs()).single.data()['selectedCafe'], 'Cafe B');
    });
  });
}
