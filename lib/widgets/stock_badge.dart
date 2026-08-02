// Copyright 2026 davidkivuyo, johnsonmushi, edwinkessy276-art, jugraki-art.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the Software;
// you may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:flutter/material.dart';

/// A compact badge that shows whether a food item is in stock or out of stock.
///
/// - [inStock] = `true` → green "In Stock" badge
/// - [inStock] = `false` → red "Out of Stock" badge with an icon
///
/// Designed to be placed at the top-right corner of a food card image or
/// next to the item title.
class StockBadge extends StatelessWidget {
  final bool inStock;
  final double fontSize;
  final double horizontalPadding;
  final double verticalPadding;

  const StockBadge({
    super.key,
    required this.inStock,
    this.fontSize = 10,
    this.horizontalPadding = 6,
    this.verticalPadding = 2,
  });

  @override
  Widget build(BuildContext context) {
    if (inStock) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFEF9A9A),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.remove_shopping_cart_outlined,
            size: fontSize + 2,
            color: const Color(0xFFC62828),
          ),
          const SizedBox(width: 3),
          Text(
            'Out of Stock',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFC62828),
            ),
          ),
        ],
      ),
    );
  }
}

/// An overlay badge that sits at the top-right corner of a food card image.
///
/// Shows the stock status with a semi-transparent background so it's
/// readable against any image.
class StockOverlayBadge extends StatelessWidget {
  final bool inStock;

  const StockOverlayBadge({super.key, required this.inStock});

  @override
  Widget build(BuildContext context) {
    if (inStock) return const SizedBox.shrink();

    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFC62828).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.block,
              size: 12,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            const Text(
              'Out of Stock',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
