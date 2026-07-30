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
import 'package:flutter/services.dart';
import '../data/food_data.dart';
import '../widgets/cafe_selection_dialog.dart';
import '../widgets/stock_badge.dart';

/// A reusable food item detail screen used from the home screen,
/// category screen, common food list, search results, and favourites.
///
/// [heroTagPrefix] must match the prefix used in the source card's [Hero]
/// tag so the Hero transition animation plays correctly.
class FoodDetailsScreen extends StatefulWidget {
  final FoodItem item;
  final String heroTagPrefix;

  const FoodDetailsScreen({
    super.key,
    required this.item,
    this.heroTagPrefix = 'home_',
  });

  @override
  State<FoodDetailsScreen> createState() => _FoodDetailsScreenState();
}

class _FoodDetailsScreenState extends State<FoodDetailsScreen> {
  int quantity = 1;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: CustomScrollView(
          slivers: [
            // Top Image Header with Back Button
            SliverAppBar(
              expandedHeight: 300.0,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag:
                          '${widget.heroTagPrefix}${item.displayCafe}_${item.title}_${item.image}',
                      child: item.buildImage(
                        width: double.infinity,
                        height: 300,
                        fit: BoxFit.cover,
                      ),
                    ),
                    // Stock overlay badge
                    StockOverlayBadge(inStock: item.available),
                    // "Bestseller" Badge - show only if featured
                    if (item.featured)
                      Positioned(
                        top: 100,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade700,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Bestseller',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Scrollable Content
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and Price
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Text(
                          'TZS ${item.price}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Subtitle
                    if (item.subtitle.isNotEmpty) ...[
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],

                    // Rating and Prep Time
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Colors.amber,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item.rating}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        if (item.time.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            '  •  ${item.time}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ],
                    ),

                    // Stock status inline
                    if (!item.available) ...[
                      const SizedBox(height: 8),
                      StockBadge(inStock: item.available, fontSize: 12),
                    ],

                    const SizedBox(height: 24),

                    // Description Section
                    if (item.description.isNotEmpty) ...[
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.description,
                        style: const TextStyle(
                          color: Colors.black54,
                          height: 1.5,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(height: 1, color: Color(0xFFEEEEEE)),
                      const SizedBox(height: 24),
                    ],

                    // Available Cafes
                    if (item.availableCafes.isNotEmpty) ...[
                      const Text(
                        'Available At',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...item.availableCafes.map(
                        (cafe) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.storefront_outlined,
                                size: 18,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                cafe,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(height: 1, color: Color(0xFFEEEEEE)),
                      const SizedBox(height: 24),
                    ],

                    // Dietary Tags
                    if (item.dietaryTags.isNotEmpty) ...[
                      const Text(
                        'Dietary Info',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: item.dietaryTags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Category
                    if (item.category.isNotEmpty) ...[
                      const Text(
                        'Category',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.category,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    const SizedBox(height: 100), // Padding for bottom navbar
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // Bottom Bar with Counter and Add to Cart Button
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Quantity Counter Block
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: () {
                        if (quantity > 1) {
                          setState(() => quantity--);
                        }
                      },
                    ),
                    Text(
                      '$quantity',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: () {
                        final maxQty = item.quantity > 0 ? item.quantity : 99;
                        if (quantity < maxQty) {
                          setState(() => quantity++);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Add to Cart Button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: item.available
                      ? () => addToCartWithCafeCheck(
                          context,
                          item,
                          quantity: quantity,
                        )
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: item.available
                        ? Colors.orange
                        : Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  icon: Icon(
                    item.available ? Icons.shopping_cart_outlined : Icons.block,
                    size: 20,
                  ),
                  label: Text(
                    item.available
                        ? 'Add to Cart • TZS ${(item.price * quantity)}'
                        : 'Unavailable',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
