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

import 'package:flutter/material.dart';
import '../data/food_data.dart';
import '../services/cart_service.dart';

Future<String?> showCafeSelectionSheet(
  BuildContext context, {
  required List<String> availableCafes,
  required String itemName,
}) {
  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Select Cafe',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose which cafe to order $itemName from:',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            ...availableCafes.map(
              (cafe) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, cafe),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      cafe,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> addToCartWithCafeCheck(BuildContext context, FoodItem item, {int quantity = 1}) async {
  final cartService = CartService();

  // Check if item is available before adding to cart
  if (!item.available) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.title} is currently unavailable'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
    }
    return;
  }

  bool success = false;

  if (item.availableCafes.length > 1) {
    final selectedCafe = await showCafeSelectionSheet(
      context,
      availableCafes: item.availableCafes,
      itemName: item.title,
    );
    if (selectedCafe == null) return;
    success = await cartService.addToCart(
      item,
      selectedCafe: selectedCafe,
      quantity: quantity,
    );
  } else if (item.availableCafes.length == 1) {
    success = await cartService.addToCart(
      item,
      selectedCafe: item.availableCafes.first,
      quantity: quantity,
    );
  } else {
    success = await cartService.addToCart(item, quantity: quantity);
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '${item.title} added to cart!'
              : 'Failed to add ${item.title} to cart. Please try again.',
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: success ? Colors.orange : Colors.red,
      ),
    );
  }
}
