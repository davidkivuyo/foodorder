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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../data/food_data.dart';
import '../data/search_bar.dart';
import '../services/app_log.dart';
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

  /// Phase 13: precache the first [limit] unique food image URLs so the
  /// hero carousels render instantly instead of showing grey placeholders
  /// while each image downloads on first display.
  static final Set<String> _precachedUrls = {};

  static void _precacheImages(List<FoodItem> items, BuildContext context) {
    if (items.isEmpty) return;
    final hasNewUrls = items.take(12).any((item) {
      final url = item.image;
      return url.isNotEmpty &&
          (url.startsWith('http://') || url.startsWith('https://')) &&
          !_precachedUrls.contains(url);
    });
    if (!hasNewUrls) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Guard against using a context whose widget was disposed before the
      // post-frame callback ran (e.g. navigating away while the frame was
      // pending). precacheImage would otherwise throw on the unmounted
      // context when resolving the image configuration.
      if (!context.mounted) return;
      var count = 0;
      for (final item in items) {
        if (count >= 12) break;
        final url = item.image;
        if (url.isEmpty ||
            !(url.startsWith('http://') || url.startsWith('https://'))) {
          continue;
        }
        if (_precachedUrls.add(url)) {
          count++;
          // On failure, drop the URL so a later build can retry it (a
          // transient failure such as offline/404 must not block retry).
          // The widget's own errorWidget handles display, and onError keeps
          // the failure suppressed (the future never completes with error).
          precacheImage(
            CachedNetworkImageProvider(url),
            context,
            onError: (_, _) => _precachedUrls.remove(url),
          );
        }
      }
    });
  }

  // THE SECTIONS COMES FROM FIRESTORE "section" COLLECTION
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
                // Phase 13: warm the image cache for the first items shown.
                _precacheImages(allItems, context);
                final validSections =
                    sections
                        .where((s) => allItems.any((f) => f.section == s.name))
                        .toList()
                      ..sort((a, b) {
                        if (a.name == 'other') return 1;
                        if (b.name == 'other') return -1;
                        return 0;
                      });

                final isDesktop = MediaQuery.of(context).size.width >= 850;

                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search bar — Shown only on mobile (desktop has top header search bar)
                        if (!isDesktop) ...[
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
                                        "Search ",
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
                        ],

                        // Promotional banner carousel
                        SpecialBannerCard(
                          imageUrls: const [
                            'https://res.cloudinary.com/nrwglbxh/image/upload/v1785401129/juicebanner_scbixp.png',
                            'https://res.cloudinary.com/nrwglbxh/image/upload/v1784272803/grilledmeat_dwcofz.png',
                            'https://res.cloudinary.com/nrwglbxh/image/upload/v1783345398/banner2_mjqb1u.png',
                          ],
                          onTap: (index) {
                            AppLog.d(
                              "Promotional Banner at index $index clicked!",
                            );
                          },
                        ),

                        const SizedBox(height: 18),

                        // ── Your Favourites section ───────────────────
                        // Appears only when favourites exist, before all
                        // other sections. Uses the existing CardRowItems.
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
                              heroTagPrefix: 'section_${section.name}_',
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
    final bool isDesktop = MediaQuery.of(context).size.width >= 850;
    final displayedItems = flipItems
        ? items.reversed.take(isDesktop ? 8 : maxItems).toList()
        : items.take(isDesktop ? 8 : maxItems).toList();

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
                  style: TextStyle(
                    fontSize: isDesktop ? 22 : 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
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
                            heroTagPrefix: heroTagPrefix,
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
        const SizedBox(height: 4),

        // Cards Presentation (Desktop Responsive Row / Carousel with hover styling)
        SizedBox(
          height: isDesktop ? 230 : 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: displayedItems.length,
            itemBuilder: (context, index) {
              final item = displayedItems[index];
              return HoverCardScale(
                child: Container(
                  width: isDesktop ? 260 : 230,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: isDesktop ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isDesktop
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isDesktop ? 8.0 : 4.0),
                                child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Food Image
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: GestureDetector(
                                onTap: () {
                                  FoodDetailsScreen.open(
                                    context,
                                    item,
                                    heroTagPrefix: heroTagPrefix,
                                  );
                                },
                                child: Hero(
                                  tag:
                                      '$heroTagPrefix${item.displayCafe}_${item.title}_${item.image}',
                                  child: item.buildImage(
                                    height: isDesktop ? 130 : 120,
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
                          padding: const EdgeInsets.all(6),
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
                                      style: TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: isDesktop ? 15 : 14,
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
                                      padding: const EdgeInsets.all(4),
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
                                        size: 16,
                                        semanticLabel: 'add item',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),

                              // Rating star & cafe name
                              Row(
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber,
                                    size: 15,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    item.averageRating > 0
                                        ? item.averageRating.toStringAsFixed(1)
                                        : '0.0',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.storefront_outlined,
                                    size: 13,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      item.displayCafe,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
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
              );
            },
          ),
        ),
      ],
    );
  }
}

class _YourFavouritesSection extends StatelessWidget {
  const _YourFavouritesSection();

  @override
  Widget build(BuildContext context) {
    final favoriteService = FavoriteService();

    return StreamBuilder<List<FoodItem>>(
      stream: favoriteService.favoriteFoodsStream(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];

        if (items.isEmpty) return const SizedBox.shrink();

        return CardRowItems(
          title: 'Your Favourites',
          items: items,
          maxItems: 5,
          heroTagPrefix: 'fav_',
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
  final String heroTagPrefix;

  const CategoriesTitles({
    super.key,
    required this.title,
    required this.items,
    this.heroTagPrefix = 'cat_',
  });

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      backgroundColor: isDesktop ? const Color(0xFFF8F9FA) : Colors.white,
      appBar: AppBar(
        title: Text(title,
            style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        centerTitle: isDesktop,
        backgroundColor: Colors.white,
        elevation: isDesktop ? 1 : 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      floatingActionButton: const CartFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isDesktop ? 700 : double.infinity),
          child: ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: HoverCardScale(
                  child: Container(
                    padding: EdgeInsets.all(isDesktop ? 16.0 : 12.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: isDesktop
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      children: [
                        // Decreased & Centered Image on White Background Card
                        Center(
                          child: Stack(
                            alignment: Alignment.topRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: GestureDetector(
                                  onTap: () {
                                    FoodDetailsScreen.open(
                                      context,
                                      item,
                                      heroTagPrefix: heroTagPrefix,
                                    );
                                  },
                                  child: Hero(
                                    tag:
                                        '$heroTagPrefix${item.displayCafe}_${item.title}_${item.image}',
                                    child: item.buildImage(
                                      height: isDesktop ? 170 : 140,
                                      width: isDesktop ? 280 : double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                              StockOverlayBadge(inStock: item.available),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Title, Price & Details
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign:
                                    isDesktop ? TextAlign.center : TextAlign.start,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'TZS ${item.price}',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: item.available
                                  ? () => addToCartWithCafeCheck(context, item)
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.all(8),
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
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        Row(
                          mainAxisAlignment: isDesktop
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${item.averageRating > 0 ? item.averageRating.toStringAsFixed(1) : '0.0'} • ',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600),
                            ),
                            Icon(Icons.storefront_outlined,
                                size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(
                              item.displayCafe,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
