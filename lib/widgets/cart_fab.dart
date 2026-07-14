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

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/cart_service.dart';
import 'cart_bottom_sheet.dart';

/// A reusable yellow floating basket button that:
/// - Appears only when the cart is not empty (animated scale).
/// - Shows a red item-count badge.
/// - Opens CartBottomSheet on tap.
///
/// Usage: set `floatingActionButton: const CartFab()` on any Scaffold.
/// Optionally provide [onOrderPlaced] to navigate after an order is placed.
class CartFab extends StatelessWidget {
  /// Called after the user successfully places an order from the cart sheet.
  /// If null, no extra navigation happens.
  final VoidCallback? onOrderPlaced;

  const CartFab({super.key, this.onOrderPlaced});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartService(),
      builder: (context, _) {
        final count = CartService().totalItemsCount;
        return AnimatedScale(
          scale: count > 0 ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          child: FloatingActionButton.extended(
            heroTag: 'cart_fab_${context.hashCode}',
            onPressed: count > 0
                ? () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => CartBottomSheet(
                        onOrderPlaced: onOrderPlaced ?? () {},
                      ),
                    );
                  }
                : null,
            backgroundColor: Colors.orange,
            foregroundColor: Colors.black87,
            elevation: 6,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  CupertinoIcons.bag_fill,
                  size: 24,
                  semanticLabel: 'basket',
                ),
                if (count > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: const Text(
              'View Basket',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        );
      },
    );
  }
}
