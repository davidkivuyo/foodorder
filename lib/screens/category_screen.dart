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
import '../widgets/cafe_selection_dialog.dart';
import '../widgets/hover_card_scale.dart';
import '../widgets/stock_badge.dart';
import 'food_details.dart';

class _Category {
  final String display;
  final String value;
  const _Category(this.display, this.value);
}

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final ValueNotifier<String> _selectedCategory = ValueNotifier('All');

  static const List<_Category> _categories = [
    _Category('🍽️ All', 'All'),
    _Category('🥞 Breakfast', 'Breakfast'),
    _Category('🍴 Lunch', 'Lunch'),
    _Category('🥮 Dinner', 'Dinner'),
    _Category('🍕 Teasers', 'Teasers'),
    _Category('🥂 Drinks', 'Drinks'),
  ];

  @override
  void dispose() {
    _selectedCategory.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FoodItem>>(
      stream: FoodData.foodItemsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                'Error loading categories: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        final allItems = snapshot.data ?? [];

        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Explore Categories',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: .75,
                    ),
                  ),
                  const Text(
                    'Find the best meal for your study break!',
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 18),
                  _buildCategoryChips(),
                  const SizedBox(height: 18),
                  // Only this subtree rebuilds when the chip changes.
                  ValueListenableBuilder<String>(
                    valueListenable: _selectedCategory,
                    builder: (context, selected, _) {
                      final filteredItems = selected == 'All'
                          ? allItems
                          : allItems
                                .where(
                                  (item) =>
                                      item.category.toLowerCase() ==
                                      selected.toLowerCase(),
                                )
                                .toList();

                      if (filteredItems.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No items found for $selected',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        );
                      }
                      return Cards(items: filteredItems);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 45,
      child: ValueListenableBuilder<String>(
        valueListenable: _selectedCategory,
        builder: (context, selected, _) {
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final category = _categories[index];
              final isSelected = category.value == selected;

              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: GestureDetector(
                  onTap: () => _selectedCategory.value = category.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFF5820D)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      border: isSelected
                          ? null
                          : Border.all(
                              color: const Color.fromARGB(255, 237, 237, 237),
                              width: 1.5,
                            ),
                    ),
                    child: Center(
                      child: Text(
                        category.display,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color.fromARGB(255, 61, 61, 61),
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class Cards extends StatelessWidget {
  final List<FoodItem> items;
  const Cards({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 850;

    if (isDesktop) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio:
              1.35, // Adjust this ratio so cards look nicely proportioned
        ),
        itemBuilder: (context, index) {
          return HoverCardScale(child: FoodCard(item: items[index]));
        },
      );
    }

    // Default mobile list
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: FoodCard(item: items[index]),
        );
      },
    );
  }
}

class FoodCard extends StatelessWidget {
  final FoodItem item;

  const FoodCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            AspectRatio(
              aspectRatio: 2.2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FoodDetailsScreen(
                          item: item,
                          heroTagPrefix: 'category_',
                        ),
                      ),
                    );
                  },
                  child: Hero(
                    tag:
                        'category_${item.displayCafe}_${item.title}_${item.image}',
                    child: item.buildImage(
                      height: 100,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            // Stock overlay badge
            StockOverlayBadge(inStock: item.available),
          ],
        ),

        Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: item.available
                        ? () => addToCartWithCafeCheck(context, item)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: item.available
                            ? Colors.orange
                            : Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.available ? Icons.add_rounded : Icons.block,
                        color: item.available
                            ? Colors.white
                            : Colors.grey.shade500,
                        size: 18,
                        semanticLabel: item.available
                            ? 'add item to cart'
                            : 'item unavailable',
                      ),
                    ),
                  ),
                ],
              ),

              Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                  Text(
                    '${item.averageRating > 0 ? item.averageRating.toStringAsFixed(1) : '0'} • ',
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.storefront_outlined,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      item.displayCafe,
                      style: const TextStyle(fontSize: 12, color: Colors.black),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/*class BottomBanner extends StatelessWidget {
  const BottomBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          // Matching the dark green shade from the design
          color: const Color(0xFF0F6322),

          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            // Content Layout
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Flash Deal Tag
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFFF5820D,
                    ), // Match your main orange color
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'FLASH DEAL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Main Heading
                const Text(
                  'Late Night Munchies',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                // Subtitle
                Text(
                  '30% off after 9 PM',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            // Positioned Party Popper Icon on the top-right
            Positioned(
              top: 0,
              right: 0,

              child: Icon(
                Icons.celebration, // Using celebration icon as the party popper
                size: 40,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}*/
