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

/// A manually created FoodItem for test scenarios.
FoodItem _testItem({
  String id = 'food_001',
  bool available = true,
}) {
  return FoodItem(
    id: id,
    image: 'https://example.com/img.jpg',
    title: 'Test Item',
    titleLower: 'test item',
    subtitle: 'Test subtitle',
    description: 'Test description',
    price: 5000,
    rating: 4.0,
    category: 'Test',
    availableCafes: ['Cafe A'],
    time: '10 min',
    section: 'test',
    available: available,
    quantity: 99,
  );
}

void main() {
  group('CartService — cart_add sync handler', () {
    late FakeFirebaseFirestore fakeFirestore;
    late CartService cartService;
    const userId = 'user_123';
    const selectedCafe = 'Cafe A';

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      cartService = CartService.testing(
        firestore: fakeFirestore,
        userId: userId,
      );
    });

    SyncOperation buildOp({
      required String itemId,
      int quantity = 2,
      String? cafe = selectedCafe,
    }) {
      return SyncOperation(
        id: 'op-$itemId',
        type: 'cart_add',
        ownerUserId: userId,
        payload: {
          'foodItemId': itemId,
          'quantity': quantity,
          'selectedCafe': cafe,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    }

    Future<List<dynamic>> cartDocs() async {
      final snapshot = await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('cart')
          .get();
      return snapshot.docs;
    }

    test('applies the operation when the food item exists and is available',
        () async {
      final item = _testItem(id: 'food_avail');
      await fakeFirestore
          .collection('food_items')
          .doc(item.id)
          .set(item.toMap());

      final success =
          await cartService.handleCartAddOp(buildOp(itemId: item.id, quantity: 3));
      expect(success, isTrue);

      final docs = await cartDocs();
      expect(docs.length, equals(1));
      expect(docs.first.id, '${item.id}_$selectedCafe');
      expect(docs.first.data()['foodItemId'], equals(item.id));
      expect(docs.first.data()['quantity'], equals(3));
    });

    test('drops the operation when the food item no longer exists', () async {
      final success = await cartService.handleCartAddOp(buildOp(itemId: 'food_gone'));
      expect(success, isTrue);

      final docs = await cartDocs();
      expect(docs, isEmpty);
    });

    test('drops the operation when the food item is unavailable', () async {
      final item = _testItem(id: 'food_soldout', available: false);
      await fakeFirestore
          .collection('food_items')
          .doc(item.id)
          .set(item.toMap());

      final success = await cartService.handleCartAddOp(buildOp(itemId: item.id));
      expect(success, isTrue);

      final docs = await cartDocs();
      expect(docs, isEmpty);
    });

    test('drops a malformed operation with no food item id', () async {
      final op = SyncOperation(
        id: 'op-malformed',
        type: 'cart_add',
        ownerUserId: userId,
        payload: {'quantity': 1},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final success = await cartService.handleCartAddOp(op);
      expect(success, isTrue);

      final docs = await cartDocs();
      expect(docs, isEmpty);
    });
  });
}
