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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:campusbite/data/food_data.dart';
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
  group('CartService — one cafe per order', () {
    late FakeFirebaseFirestore fakeFirestore;
    late CartService cartService;
    const userId = 'user_123';

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // The offline path mutates the local cart list directly, which is what
      // this suite needs to exercise the cafe-conflict guard deterministically.
      ConnectivityService.setMockInstance(
        ConnectivityService.testing(initialOnline: false),
      );
      fakeFirestore = FakeFirebaseFirestore();
      cartService = CartService.testing(
        firestore: fakeFirestore,
        userId: userId,
      );
    });

    test('empty cart never conflicts', () {
      expect(cartService.cafeConflictWithCart('Cafe A', _testItem()), isNull);
      expect(cartService.cafeConflictWithCart(null, _testItem()), isNull);
    });

    test('adding from a different cafe is refused and names the cart cafe',
        () async {
      final itemA = _testItem(id: 'food_a', availableCafes: const ['Cafe A']);
      final itemB = _testItem(id: 'food_b', availableCafes: const ['Cafe B']);

      expect(await cartService.addToCart(itemA, selectedCafe: 'Cafe A'), isTrue);
      expect(cartService.cartItems, hasLength(1));

      expect(
        await cartService.addToCart(itemB, selectedCafe: 'Cafe B'),
        isFalse,
        reason: 'mixing cafes must be refused',
      );
      expect(
        cartService.cafeConflictWithCart('Cafe B', itemB),
        'Cafe A',
        reason: 'the conflicting cart cafe is reported',
      );
      expect(
        cartService.cartItems,
        hasLength(1),
        reason: 'the conflicting item must not be added',
      );
    });

    test('adding another item from the same cafe succeeds', () async {
      final itemA = _testItem(id: 'food_a', availableCafes: const ['Cafe A']);
      final itemA2 = _testItem(id: 'food_a2', availableCafes: const ['Cafe A']);

      expect(await cartService.addToCart(itemA, selectedCafe: 'Cafe A'), isTrue);
      expect(await cartService.addToCart(itemA2, selectedCafe: 'Cafe A'), isTrue);
      expect(cartService.cartItems, hasLength(2));
    });

    test('increasing the quantity of an existing cart item succeeds', () async {
      final itemA = _testItem(id: 'food_a', availableCafes: const ['Cafe A']);

      expect(await cartService.addToCart(itemA, selectedCafe: 'Cafe A'), isTrue);
      expect(await cartService.addToCart(itemA, selectedCafe: 'Cafe A'), isTrue);
      expect(cartService.cartItems, hasLength(1));
      expect(cartService.cartItems.first.quantity, 2);
    });

    test('off-campus item (no cafe) conflicts with a campus-cafe item', () async {
      final itemA = _testItem(id: 'food_a', availableCafes: const ['Cafe A']);
      final offCampus = _testItem(id: 'food_off', availableCafes: const []);

      expect(await cartService.addToCart(itemA, selectedCafe: 'Cafe A'), isTrue);
      expect(await cartService.addToCart(offCampus), isFalse);
    });

    test('items without a cafe can be combined', () async {
      final offCampus1 = _testItem(id: 'food_off1', availableCafes: const []);
      final offCampus2 = _testItem(id: 'food_off2', availableCafes: const []);

      expect(await cartService.addToCart(offCampus1), isTrue);
      expect(await cartService.addToCart(offCampus2), isTrue);
      expect(cartService.cartItems, hasLength(2));
    });

    test('multi-cafe item without a selection is cafeless-classed exactly '
        'like the persisted path', () async {
      final offCampus = _testItem(id: 'food_off', availableCafes: const []);
      final multi = _testItem(
        id: 'food_multi',
        availableCafes: const ['Cafe A', 'Cafe B'],
      );

      // Cart holds a genuinely cafeless item (selectedCafe null → '' class).
      expect(await cartService.addToCart(offCampus), isTrue);

      // A multi-cafe item added without a selection resolves to null (''),
      // exactly like _resolveCafe/_persistedCafeOf — it must NOT fall back
      // to the joined displayCafe ('Cafe A, Cafe B'), which would falsely
      // conflict with the cafeless item already in the cart.
      expect(await cartService.addToCart(multi), isTrue);
      expect(cartService.cartItems, hasLength(2));
      expect(cartService.cartItems.last.selectedCafe, isNull);
    });

    test('multi-cafe item without a selection still conflicts with a '
        'single-cafe item', () async {
      final itemA = _testItem(id: 'food_a', availableCafes: const ['Cafe A']);
      final multi = _testItem(
        id: 'food_multi',
        availableCafes: const ['Cafe A', 'Cafe B'],
      );

      expect(await cartService.addToCart(itemA, selectedCafe: 'Cafe A'), isTrue);
      // Cafeless ('' ) vs 'Cafe A' — different classes, refused.
      expect(await cartService.addToCart(multi), isFalse);
      expect(cartService.cartItems, hasLength(1));
    });

    test('adding then removing a single-cafe item without a cafe resolves '
        'the implicit cafe consistently', () async {
      final itemA = _testItem(id: 'food_a', availableCafes: const ['Cafe A']);

      // Add without an explicit selection: the single canonical cafe is
      // resolved and stored.
      expect(await cartService.addToCart(itemA), isTrue);
      expect(cartService.cartItems, hasLength(1));
      expect(cartService.cartItems.first.selectedCafe, 'Cafe A');

      // Remove without an explicit selection: the same implicit resolution
      // must find and remove the item.
      await cartService.removeFromCart(itemA);
      expect(cartService.cartItems, isEmpty,
          reason: 'removal must resolve the implicit cafe like the add does');

      // The cart is reusable for a different cafe afterwards.
      final itemB = _testItem(id: 'food_b', availableCafes: const ['Cafe B']);
      expect(await cartService.addToCart(itemB), isTrue);
      expect(cartService.cartItems, hasLength(1));
      expect(cartService.cartItems.first.selectedCafe, 'Cafe B');
    });

    test('deleteFromCart without a cafe resolves the implicit cafe and '
        'empties the cart', () async {
      final itemA = _testItem(id: 'food_a', availableCafes: const ['Cafe A']);

      expect(await cartService.addToCart(itemA), isTrue);
      expect(cartService.cartItems, hasLength(1));

      await cartService.deleteFromCart(itemA);
      expect(cartService.cartItems, isEmpty,
          reason: 'delete must resolve the implicit cafe like the add does');
    });
  });
}
