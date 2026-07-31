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

/*If you want to add some logics over the banner click go to line 145, OR
you can use the onTap callback to handle the click event and perform any
desired actions based on the index of the clicked banner.
*/

import 'package:flutter/material.dart';
import '../data/food_data.dart';
import '../data/search_bar.dart';
import '../services/favorite_service.dart';
import '../widgets/cafe_selection_dialog.dart';
import '../widgets/cart_fab.dart';
import '../widgets/hover_card_scale.dart';
import '../widgets/special_banner_card.dart';
import '../widgets/stock_badge.dart';
import 'common_food.dart';
import 'favorites_screen.dart';
import 'food_details.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const Map<String, String> _sectionTitles = {
    'campus_favourite': 'Favourite on campus',
    'todays_deals': "Today's Deals",
    'drinks': 'Drinks Deals!',
    'other': 'Other meal deals',
  };

  String _formatTitle(String name) {
    if (_sectionTitles.containsKey(name)) return _sectionTitles[name]!;
    return name
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Section>>(
          stream: FoodData.sectionsStream,
          builder: (context, sectionsSnapshot) {
            if (sectionsSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final sections = sectionsSnapshot.data ?? [];

            return StreamBuilder<List<FoodItem>>(
              stream: FoodData.foodItemsStream,
              builder: (context, foodSnapshot) {
                if (foodSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (foodSnapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        'Error loading meals: ${foodSnapshot.error}',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final allItems = foodSnapshot.data ?? [];
                final validSections =
                    sections
                        .where((s) => allItems.any((f) => f.section == s.name))
                        .toList()
                      ..sort((a, b) {
                        if (a.name == 'other') return 1;
                        if (b.name == 'other') return -1;
                        return 0;
                      });

                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search bar
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SearchBarScreen(),
                                ),
                              );
                            },
                            child: Container(
                              height: 56,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.search,
                                    color: Colors.black87,
                                    size: 24,
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      "Search your next meal",
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Promotional banner carousel
                        SpecialBannerCard(
                          imageUrls: const [
                            'https://res.cloudinary.com/nrwglbxh/image/upload/v1785401129/juicebanner_scbixp.png',
                            'https://res.cloudinary.com/nrwglbxh/image/upload/v1784272803/grilledmeat_dwcofz.png',
                            'https://res.cloudinary.com/nrwglbxh/image/upload/v1783345398/banner2_mjqb1u.png',
                          ],
                          onTap: (index) {
                            debugPrint(
                              "Promotional Banner at index $index clicked!",
                            );
                          },
                        ),

                        const SizedBox(height: 18),

                        // ── Your Favourites section ───────────────────
                        // Appears only when favourites exist, before all
                        // other sections.  Uses the existing CardRowItems.
                        const _YourFavouritesSection(),

                        // Dynamic sections from firestore
                        ...validSections.expand((section) {
                          final sectionItems = allItems
                              .where((f) => f.section == section.name)
                              .toList();
                          if (sectionItems.isEmpty) return <Widget>[];
                          return [
                            CardRowItems(
                              title: _formatTitle(section.name),
                              items: sectionItems,
                            ),
                            const Divider(),
                          ];
                        }),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Common loved foods',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        const CommonFood(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class CardRowItems extends StatelessWidget {
  final String title;
  final List<FoodItem> items;
  final int maxItems;
  final bool flipItems;
  final VoidCallback? arrowBuilder;
  final String heroTagPrefix;

  const CardRowItems({
    super.key,
    required this.title,
    required this.items,
    this.maxItems = 5,
    this.flipItems = false,
    this.arrowBuilder,
    this.heroTagPrefix = 'home_',
  });

  @override
  Widget build(BuildContext context) {
    final displayedItems = flipItems
        ? items.reversed.take(maxItems).toList()
        : items.take(maxItems).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Menu Header Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed:
                    arrowBuilder ??
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CategoriesTitles(
                            title: title,
                            items: flipItems ? items.reversed.toList() : items,
                          ),
                        ),
                      );
                    },
                icon: const Icon(
                  Icons.arrow_forward,
                  semanticLabel: 'more items',
                ),
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  iconSize: 19,
                ),
              ),
            ],
          ),
        ),

        // Horizontal Scrollable Cards List — with hover animation on desktop
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: displayedItems.length,
            itemBuilder: (context, index) {
              final item = displayedItems[index];
              return HoverCardScale(
                child: Container(
                  width: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Card(
                      elevation: 0,
                      color: Colors.transparent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Food Image
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => FoodDetailsScreen(
                                          item: item,
                                          heroTagPrefix: heroTagPrefix,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Hero(
                                    tag:
                                        '$heroTagPrefix${item.displayCafe}_${item.title}_${item.image}',
                                    child: item.buildImage(
                                      height: 120,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                              // Stock overlay badge
                              StockOverlayBadge(inStock: item.available),
                            ],
                          ),

                          // Card Details
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                                Text(
                                  '${item.subtitle} • ${item.time}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),

                                // Rating & Cafe Display Row
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                    Text(
                                      '${item.averageRating > 0 ? item.averageRating.toStringAsFixed(1) : '0.0'} • ',
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
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Renders the "Your Favourites" section on the Home Screen.
///
/// Fetches favourite food items via [FavoriteService] and displays
/// them in the existing [CardRowItems] horizontal carousel.
/// The section is hidden when no favourites exist (stream is empty).
class _YourFavouritesSection extends StatelessWidget {
  const _YourFavouritesSection();

  @override
  Widget build(BuildContext context) {
    final favoriteService = FavoriteService();

    return StreamBuilder<List<FoodItem>>(
      stream: favoriteService.favoriteFoodsStream(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];

        // Hide the section completely when no favourites exist.
        if (items.isEmpty) return const SizedBox.shrink();

        return CardRowItems(
          title: 'Your Favourites',
          items: items,
          maxItems: 5,
          heroTagPrefix: 'fav_',
          // Override the default arrow to navigate to YourFavouritesScreen.
          arrowBuilder: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const YourFavouritesScreen()),
          ),
        );
      },
    );
  }
}

class CategoriesTitles extends StatelessWidget {
  final String title;
  final List<FoodItem> items;

  const CategoriesTitles({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      floatingActionButton: const CartFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: ListView.builder(
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
                                  builder: (_) =>
                                      FoodDetailsScreen(item: item),
                                ),
                              );
                            },
                            child: Hero(
                              tag:
                                  'home_${item.displayCafe}_${item.title}_${item.image}',
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
                                  item.available
                                      ? Icons.add_rounded
                                      : Icons.block,
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

                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 16,
                            ),
                            Text(
                              '${item.averageRating > 0 ? item.averageRating.toStringAsFixed(1) : '0.0'} • ',
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
