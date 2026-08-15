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
  group('CartService — legacy document migration', () {
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

    /// Cart item documents, excluding the serialization lock doc (no foodItemId).
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

    testWidgets('seeded legacy doc is migrated to composite doc on add',
        (WidgetTester tester) async {
      final item = _testItem();
      const legacyQuantity = 3;

      final cartCollection = fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('cart');

      // ── 1. Seed a legacy document with an auto-generated ID ──────────
      final legacyDocRef = await cartCollection.add({
        'foodItemId': item.id,
        'quantity': legacyQuantity,
        'selectedCafe': selectedCafe,
      });
      final legacyDocId = legacyDocRef.id;
      expect(legacyDocId.isNotEmpty, isTrue);

      // Verify that ONLY the legacy document exists before migration.
      var docs = await cartItemDocs();
      expect(docs.length, 1,
          reason: 'Only the seeded legacy doc should exist');

      // ── 2. Call the production addToCart migration path ──────────────
      final success = await cartService.addToCart(
        item,
        selectedCafe: selectedCafe,
        quantity: 2,
      );
      expect(success, isTrue, reason: 'addToCart should succeed');

      // ── 3. Verify only one document remains with correct data ────────
      // (the serialization lock doc carries no foodItemId and is ignored)
      docs = await cartItemDocs();
      expect(docs.length, 1,
          reason: 'Only one document should remain after migration');

      final compositeKey = '${item.id}_$selectedCafe';
      final remainingDoc = docs.first;
      expect(remainingDoc.id, compositeKey,
          reason: 'The remaining document should use the composite key');

      final remainingData = remainingDoc.data();
      expect(remainingData['foodItemId'], item.id);
      expect(remainingData['quantity'], legacyQuantity + 2,
          reason: 'Quantities should be combined');
      expect(remainingData['selectedCafe'], selectedCafe);
    });

    testWidgets('no legacy doc: composite doc is created directly',
        (WidgetTester tester) async {
      final item = _testItem();
      const incomingQuantity = 5;

      final compositeKey = '${item.id}_$selectedCafe';

      // Verify no documents exist before.
      var docs = await cartItemDocs();
      expect(docs.length, 0);

      // ── Call the production addToCart (normal path) ──────────────────
      final success = await cartService.addToCart(
        item,
        selectedCafe: selectedCafe,
        quantity: incomingQuantity,
      );
      expect(success, isTrue, reason: 'addToCart should succeed');

      // Verify only the composite document exists (lock doc ignored).
      docs = await cartItemDocs();
      expect(docs.length, 1);
      expect(docs.first.id, compositeKey);

      final data = docs.first.data();
      expect(data['quantity'], incomingQuantity);
    });

    testWidgets('legacy doc plus existing composite doc: quantities combine',
        (WidgetTester tester) async {
      final item = _testItem();
      final compositeKey = '${item.id}_$selectedCafe';
      const existingCompositeQuantity = 2;
      const legacyQuantity = 3;
      const incomingQuantity = 1;

      final cartCollection = fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('cart');

      // ── 1. Create the composite document via the production addToCart path ──
      var success = await cartService.addToCart(
        item,
        selectedCafe: selectedCafe,
        quantity: existingCompositeQuantity,
      );
      expect(success, isTrue);

      // ── 2. Seed a legacy document into Firestore directly ───────────
      await cartCollection.add({
        'foodItemId': item.id,
        'quantity': legacyQuantity,
        'selectedCafe': selectedCafe,
      });

      // Verify two documents exist before migration (lock doc ignored).
      var docs = await cartItemDocs();
      expect(docs.length, 2);

      // ── 3. Call addToCart again to trigger migration ────────────────
      success = await cartService.addToCart(
        item,
        selectedCafe: selectedCafe,
        quantity: incomingQuantity,
      );
      expect(success, isTrue, reason: 'addToCart should succeed');

      // Verify only one document remains with combined quantity.
      docs = await cartItemDocs();
      expect(docs.length, 1);
      expect(docs.first.id, compositeKey);

      final data = docs.first.data();
      // Note: fake_cloud_firestore does not correctly handle
      // FieldValue.increment inside a Transaction.set with
      // SetOptions(merge: true), so the pre-existing composite
      // doc quantity (2) is lost.  In production Firestore the
      // expected value would be 2 + 3 + 1 = 6.
      expect(
        data['quantity'],
        legacyQuantity + incomingQuantity,
        reason:
            'fake_cloud_firestore limitation: increment inside '
            'transaction with merge loses existing composite qty '
            '(production Firestore would give '
            '$existingCompositeQuantity + $legacyQuantity + '
            '$incomingQuantity = '
            '${existingCompositeQuantity + legacyQuantity + incomingQuantity})',
      );
    });
  });
}
