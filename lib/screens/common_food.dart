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
import 'package:cached_network_image/cached_network_image.dart';
import '../data/food_data.dart';
import '../widgets/cafe_selection_dialog.dart';
import '../widgets/cart_fab.dart';
import '../widgets/stock_badge.dart';
import 'food_details.dart';

// ---------------------------------------------------------------------------
// Data model for a common-food category shown in the horizontal scroll list.
// Images are placeholder Firebase Storage URLs – ready to be replaced with
// real URLs fetched from Firestore once that phase is activated.
// ---------------------------------------------------------------------------
class _CommonFoodItem {
  final String title;
  final String prepTime;
  final String imageUrl; // Firebase Storage URL (placeholder for now)

  const _CommonFoodItem({
    required this.title,
    required this.prepTime,
    required this.imageUrl,
  });
}

// Static mock data – images are grey placeholders that will later be replaced
// by real Firebase Storage URLs fetched from Firestore.
const List<_CommonFoodItem> _commonFoods = [
  _CommonFoodItem(
    title: 'Wali',
    prepTime: '20-30min',
    imageUrl:
        'https://res.cloudinary.com/nrwglbxh/image/upload/v1783345341/ricemeat_vstzgy.jpg', // will be fetched from Firebase Storage
  ),
  _CommonFoodItem(
    title: 'Ugali',
    prepTime: '20-30min',
    imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/4/48/Ugali_%26_Sukuma_Wiki.jpg', // will be fetched from Firebase Storage
  ),
  _CommonFoodItem(
    title: 'Chips',
    prepTime: '30-40min',
    imageUrl:
        'https://res.cloudinary.com/nrwglbxh/image/upload/v1783345370/chipss_b7junj.jpg', // will be fetched from Firebase Storage
  ),
  _CommonFoodItem(
    title: 'Pilau',
    prepTime: '20-30min',
    imageUrl:
        'https://res.cloudinary.com/nrwglbxh/image/upload/v1783345276/biriyanimeat_bofprw.jpg', // will be fetched from Firebase Storage
  ),
];

// ---------------------------------------------------------------------------
// CommonFood – horizontal scrollable list of circular food category items.
// Shown on the home screen via CommonFood().
// ---------------------------------------------------------------------------
class CommonFood extends StatelessWidget {
  const CommonFood({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _commonFoods.length,
        separatorBuilder: (_, _) => const SizedBox(width: 20),
        itemBuilder: (context, index) {
          final food = _commonFoods[index];
          return _CommonFoodCircle(food: food);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A single circular item in the horizontal list.
// ---------------------------------------------------------------------------
class _CommonFoodCircle extends StatelessWidget {
  final _CommonFoodItem food;

  const _CommonFoodCircle({required this.food});

  Widget _buildCircleImage() {
    final bool hasUrl =
        food.imageUrl.startsWith('http://') ||
        food.imageUrl.startsWith('https://');

    if (hasUrl) {
      return CachedNetworkImage(
        imageUrl: food.imageUrl,
        imageBuilder: (context, imageProvider) => Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
          ),
        ),
        placeholder: (context, url) => _placeholder(),
        errorWidget: (context, url, error) => _placeholder(),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: 72,
      height: 72,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: const Icon(Icons.restaurant, size: 32, color: Colors.black),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => _CommonFoodList(food: food)),
        );
      },
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: ClipOval(child: _buildCircleImage()),
            ),
            const SizedBox(height: 6),
            Text(
              food.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  food.prepTime,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CommonFoodList – vertical list of food items corresponding to the tapped
// common-food category.  Layout mirrors the category screen (FoodCard style).
// No AppBar – uses a custom back button instead.
// ---------------------------------------------------------------------------
class _CommonFoodList extends StatelessWidget {
  final _CommonFoodItem food;

  const _CommonFoodList({required this.food});

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 850;

    return Scaffold(
      floatingActionButton: isDesktop ? null : const CartFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: StreamBuilder<List<FoodItem>>(
          stream: FoodData.foodItemsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(
                    'Error loading items: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final allItems = snapshot.data ?? [];
            final filtered = allItems.where((item) {
              return item.title.toLowerCase().contains(
                food.title.toLowerCase(),
              );
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Custom header (no AppBar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          food.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Responsive food layout ──────────────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.restaurant_menu,
                                  size: 64,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No ${food.title} items available yet.',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : isDesktop
                      ? GridView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: filtered.length,
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 320,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: 1.35,
                              ),
                          itemBuilder: (context, index) {
                            return _CommonFoodCard(item: filtered[index]);
                          },
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(10.0),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 24.0),
                              child: _CommonFoodCard(item: item),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CommonFoodCard – single food card in the vertical list.
// Layout identical to the category screen's FoodCard.
// ---------------------------------------------------------------------------
class _CommonFoodCard extends StatelessWidget {
  final FoodItem item;

  const _CommonFoodCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Food image (tappable → detail screen) ───────────────────────
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
                          heroTagPrefix: 'common_',
                        ),
                      ),
                    );
                  },
                  child: Hero(
                    tag:
                        'common_${item.displayCafe}_${item.title}_${item.image}',
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
            // Prep time overlay badge (Deliveroo style)
            PrepTimeBadge(time: item.time),
          ],
        ),

        // ── Card details ────────────────────────────────────────────────
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
                  // Add to cart button
                  GestureDetector(
                    onTap: item.available
                        ? () => addToCartWithCafeCheck(context, item)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: item.available
                            ? const Color(0xFFF5820D)
                            : Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.available ? Icons.add_rounded : Icons.block,
                        color: item.available
                            ? Colors.white
                            : Colors.grey.shade500,
                        size: 18,
                        semanticLabel: 'add item',
                      ),
                    ),
                  ),
                ],
              ),

              // Rating & cafe row
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
