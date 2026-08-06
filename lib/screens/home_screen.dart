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

                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search bar
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                28,
                              ), // Fixed ripple effect to match container pill shape
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SearchBarScreen(),
                                  ),
                                );
                              },
                              // Ink (not Container) paints the fill onto the
                              // Material so the InkWell ripple renders visibly
                              // over the field instead of behind the opaque
                              // background.
                              child: Ink(
                                height:
                                    50, // Proportional height matching Deliveroo's standard search bar
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors
                                      .white, // Off-white/white interior fill
                                  border: Border.all(
                                    color: Colors
                                        .grey
                                        .shade300, // Light grey outline matching the screenshot
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.search,
                                      color: Colors.grey.shade700,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "Dishes, categories, tags", // Updated placeholder text
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w400,
                                          color: Colors
                                              .grey
                                              .shade600, // Styled as placeholder hint text
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
                            AppLog.d(
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
                              heroTagPrefix: 'section_${section.name}_',
                            ),
                            // Minimal gap between consecutive horizontal
                            // section lists — the hairline separator stays,
                            // but the default 16px Divider height is halved.
                            const Divider(height: 8),
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

        // Horizontal Scrollable Cards List — with hover animation on desktop
        SizedBox(
          height:
              250, // Updated height to comfortably fit image, text, and rating
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            // Side spacing lives INSIDE the scroll view so the first card
            // rests 8px from the phone screen edge (matching the
            // SpecialBannerCard carousel) while cards still slide under the
            // screen edge when the user scrolls — the list spans the full
            // screen width and is never clipped at an inset boundary.
            padding: const EdgeInsets.only(left: 8),
            itemCount: displayedItems.length,
            itemBuilder: (context, index) {
              final item = displayedItems[index];
              return HoverCardScale(
                child: Container(
                  width: 260, // Deliveroo-style wide card aspect ratio
                  margin: const EdgeInsets.only(
                    right: 12,
                  ), // Standard spacing between cards
                  child: Card(
                    elevation: 0,
                    color: Colors.transparent,
                    margin: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Food Image Stack
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                16,
                              ), // Retained border radius
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
                                    height:
                                        140, // Expanded image height for proportional fit
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),

                            // Delivery Time Badge (Bottom-Right Overlay as in Deliveroo)
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.1,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  item.time,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),

                            // Stock overlay badge
                            StockOverlayBadge(inStock: item.available),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Card Details
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title & Quick-Add Button Row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // IconButton (not GestureDetector) so the
                                  // quick-add control is focusable and
                                  // keyboard-activatable, with a tooltip that
                                  // doubles as its accessible label.
                                  IconButton(
                                    onPressed: item.available
                                        ? () => addToCartWithCafeCheck(
                                            context,
                                            item,
                                          )
                                        : null,
                                    tooltip: item.available
                                        ? 'Add ${item.title} to cart'
                                        : '${item.title} is unavailable',
                                    icon: Icon(
                                      item.available
                                          ? Icons.add_rounded
                                          : Icons.block,
                                      color: item.available
                                          ? Colors.white
                                          : Colors.grey.shade500,
                                      size: 16,
                                    ),
                                    style: IconButton.styleFrom(
                                      // Matches the previous circular badge:
                                      // 16px icon inside 5px padding => 26px.
                                      backgroundColor: item.available
                                          ? Colors.orange
                                          : Colors.grey.shade300,
                                      disabledBackgroundColor:
                                          Colors.grey.shade300,
                                      shape: const CircleBorder(),
                                      padding: const EdgeInsets.all(5),
                                      iconSize: 16,
                                      minimumSize: const Size.square(26),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 4),

                              // Rating Row (Star icon + Rate ONLY, no distance or review count)
                              Row(
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Colors
                                        .amber, // Deliveroo green star indicator
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.averageRating > 0
                                        ? item.averageRating.toStringAsFixed(1)
                                        : '0.0',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '• ${item.displayCafe}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              /*
                              // PROMOTIONAL TEXT BADGE (Commented out for future use)
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFECEB), // Light pink/red promo background
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Spend £10, Get £0 delivery fee',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Color(0xFFD9251A),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              */
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
  final String heroTagPrefix;

  const CategoriesTitles({
    super.key,
    required this.title,
    required this.items,
    this.heroTagPrefix = 'cat_title_',
  });

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
