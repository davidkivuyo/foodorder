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
import '../services/favorite_service.dart';
import '../widgets/cafe_selection_dialog.dart';
import '../widgets/cart_fab.dart';
import '../widgets/hover_card_scale.dart';
import '../widgets/stock_badge.dart';
import 'food_details.dart';

/// Full-screen vertical list of all favourite food items.
///
/// Reuses the existing food card layout from [CategoriesTitles].
/// No maximum limit — every favourite is displayed here.
class YourFavouritesScreen extends StatelessWidget {
  const YourFavouritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final favoriteService = FavoriteService();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Your Favourites',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: const CartFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: StreamBuilder<List<FoodItem>>(
        stream: favoriteService.favoriteFoodsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('Something went wrong. Please try again.'),
            );
          }
          final items = snapshot.data ?? [];

          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No favourites yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Order and collect meals to build your favourites.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(10.0),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: HoverCardScale(
                  child: Column(
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
                                        heroTagPrefix: 'fav_',
                                      ),
                                    ),
                                  );
                                },
                                child: Hero(
                                  tag:
                                      'fav_${item.displayCafe}_${item.title}_${item.image}',
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
                                      ? () => addToCartWithCafeCheck(
                                          context,
                                          item,
                                        )
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
                                      item.available
                                          ? Icons.add_rounded
                                          : Icons.block,
                                      color: item.available
                                          ? Colors.white
                                          : Colors.grey.shade500,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Colors.amber,
                                  size: 16,
                                ),
                                Text(
                                  '${item.rating} • ',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black,
                                  ),
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
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            StockBadge(inStock: item.available, fontSize: 11),
                          ],
                        ),
                      ),
                    ],
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
