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
import '../utils/responsive.dart';
import '../widgets/cafe_selection_dialog.dart';
import '../widgets/cart_fab.dart';
import '../widgets/special_banner_card.dart';
import '../widgets/stock_badge.dart';
import 'common_food.dart';
import 'favorites_screen.dart';
import 'food_details.dart';

class HomeScreen extends StatelessWidget {
  final ScrollController? scrollController;

  const HomeScreen({super.key, this.scrollController});

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

  static void _openSearch(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchBarScreen()),
    );
  }

  // THE SECTIONS COMES FROM FIRESTORE "section" COLLECTION
  static const Map<String, String> _sectionTitles = {
    'campus_favourite': 'Campus favourites',
    'todays_deals': "Today's menu",
    'drinks': 'Drinks Deals',
    'other': 'Hot spots',
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
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: StreamBuilder<List<Section>>(
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

              final isDesktop = isDesktopWidth(context);
              final double textScale = MediaQuery.textScalerOf(
                context,
              ).scale(1.0);

              return SingleChildScrollView(
                controller: scrollController,
                child: Stack(
                  children: [
                    // ── 1. Orange Header Overlay Background ─────────────
                    // Spans from notification status bar at top edge down to
                    // center of special banner card (Mobile / Small screens only)
                    if (!isDesktop)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: statusBarHeight + 12 + 48 * textScale + 8,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(20),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? 8.0 : 0,
                        isDesktop ? 8.0 : 12.0,
                        isDesktop ? 8.0 : 0,
                        8.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Search bar — Shown only on mobile (desktop has
                          // top header search bar)
                          if (!isDesktop) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Semantics(
                                button: true,
                                label: 'Open search',
                                onTap: () => HomeScreen._openSearch(context),
                                excludeSemantics: true,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(24),
                                  onTap: () => HomeScreen._openSearch(context),
                                  child: Container(
                                    height: 48 * textScale,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.search,
                                          color: Colors.grey.shade600,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            "Menu, categories, tags",
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: Colors.grey.shade600,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Promotional banner carousel
                          SpecialBannerCard(
                            imageUrls: const [
                              'https://res.cloudinary.com/nrwglbxh/image/upload/v1785401129/juicebanner_scbixp.png',
                              'https://res.cloudinary.com/nrwglbxh/image/upload/v1784272803/grilledmeat_dwcofz.png',
                              'https://res.cloudinary.com/nrwglbxh/image/upload/v1783345398/banner2_mjqb1u.png',
                            ],
                            horizontalPadding: 8.0,
                            onTap: (index) {
                              AppLog.d(
                                "Promotional Banner at index $index clicked!",
                              );
                            },
                          ),

                          const SizedBox(height: 18),

                          // ── Your Favourites section ───────────────
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
                            ];
                          }),

                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
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
                          const SizedBox(height: 8),
                          const CommonFood(),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
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
    final bool isDesktop = isDesktopWidth(context);
    final double textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final displayedItems = flipItems
        ? items.reversed.take(isDesktop ? 8 : maxItems).toList()
        : items.take(isDesktop ? 8 : maxItems).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Menu Header Row — Uber Eats style title & action button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
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
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  // Compact visual footprint: the 48×48 tap target comes from
                  // the padded tap-target size (which expands the hit area
                  // without growing the visible circle), not from the visual
                  // minimum.
                  minimumSize: const Size.square(36),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Cards Presentation (Desktop Responsive Row)
        SizedBox(
          height: (isDesktop ? 230 : 208) * textScale,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(8, 0, isDesktop ? 8 : 0, 0),
            itemCount: displayedItems.length,
            itemBuilder: (context, index) {
              final item = displayedItems[index];
              final bool isAvailable = item.available;
              return Container(
                width: isDesktop ? 265 : 235,
                margin: const EdgeInsets.only(right: 12),
                child: Padding(
                  padding: EdgeInsets.all(isDesktop ? 8.0 : 4.0),
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
                          StockOverlayBadge(inStock: isAvailable),
                          // Prep time overlay badge (Deliveroo style)
                          PrepTimeBadge(time: item.time),
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
                                IconButton(
                                  onPressed: isAvailable
                                      ? () => addToCartWithCafeCheck(
                                          context,
                                          item,
                                        )
                                      : null,
                                  icon: Icon(
                                    isAvailable
                                        ? Icons.add_rounded
                                        : Icons.block,
                                    semanticLabel: isAvailable
                                        ? 'Add item to cart'
                                        : 'Item unavailable',
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: isAvailable
                                        ? Colors.orange
                                        : Colors.grey.shade300,
                                    foregroundColor: isAvailable
                                        ? Colors.white
                                        : Colors.grey.shade500,
                                    padding: EdgeInsets.zero,
                                    iconSize: 16,
                                    minimumSize: const Size.square(24),
                                    tapTargetSize: MaterialTapTargetSize.padded,
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
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
          child: Divider(height: 1, thickness: 0.5, color: Color(0xFFE0E0E0)),
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
    final bool isDesktop = isDesktopWidth(context);

    return Scaffold(
      backgroundColor: isDesktop ? const Color(0xFFF8F9FA) : Colors.white,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: isDesktop,
        backgroundColor: Colors.white,
        elevation: isDesktop ? 1 : 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      floatingActionButton: const CartFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 700 : double.infinity,
          ),
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No food items available in this category.',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10.0),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: Column(
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
                                    const SizedBox(width: 8),
                                    Text(
                                      'TZS ${item.price}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Add to cart button
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
                                          semanticLabel: item.available
                                              ? 'Add item to cart'
                                              : 'Item unavailable',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Rating & cafe row
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                    Text(
                                      '${item.averageRating > 0 ? item.averageRating.toStringAsFixed(1) : '0'} • ',
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
                    );
                  },
                ),
        ),
      ),
    );
  }
}
