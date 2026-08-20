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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/home_screen.dart';
import '../screens/account_screen.dart';
import '../screens/category_screen.dart';
import '../screens/order_screen.dart';
import '../screens/food_details.dart';
import '../data/search_bar.dart';
import '../data/food_data.dart';
import 'package:dash_no_internet_screen/dash_no_internet_screen.dart';
import '../services/cart_service.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';
import '../widgets/cart_bottom_sheet.dart';
import '../widgets/cart_fab.dart';
import '../widgets/offline_banner.dart';
import '../utils/responsive.dart';

/// Describes a desktop filter chip: its display label, title shown on the
/// results screen, icon, and the section/availability value used for
/// filtering. Keeps filtering keyed on data, not on display labels.
class _FilterDescriptor {
  final String label;
  final String title;
  final IconData icon;
  final String section;

  const _FilterDescriptor({
    required this.label,
    required this.title,
    required this.icon,
    required this.section,
  });
}

const List<_FilterDescriptor> _filterDescriptors = [
  _FilterDescriptor(
    label: 'All Foods',
    title: 'All Foods',
    icon: Icons.grid_view_rounded,
    section: 'all',
  ),
  _FilterDescriptor(
    label: "🔥 Today's Deals",
    title: "Today's Deals",
    icon: Icons.local_fire_department,
    section: 'todays_deals',
  ),
  _FilterDescriptor(
    label: "⭐ Campus Favourite",
    title: 'Favourite on campus',
    icon: Icons.star_rounded,
    section: 'campus_favourite',
  ),
  _FilterDescriptor(
    label: '🍹 Drinks Deals!',
    title: 'Drinks Deals!',
    icon: Icons.local_drink_rounded,
    section: 'drinks',
  ),
  _FilterDescriptor(
    label: '🍱 Other Meal Deals',
    title: 'Other meal deals',
    icon: Icons.restaurant_rounded,
    section: 'other',
  ),
  _FilterDescriptor(
    label: '✅ Available Now',
    title: 'Available Now',
    icon: Icons.check_circle_outline,
    section: 'available',
  ),
];

// home screen
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _NavigationExampleState();
}

// body and bottom navigation
class _NavigationExampleState extends State<MainScreen> {
  int currentPageIndex = 0;
  final ScrollController _homeScrollController = ScrollController();
  bool _isScrolled = false;

  final TextEditingController _desktopSearchController =
      TextEditingController();
  final FocusNode _desktopSearchFocusNode = FocusNode();
  bool _isDesktopSearchOpen = false;
  String _desktopSearchQuery = '';
  Stream<int>? _unreadCountStream;
  StreamSubscription<User?>? _authSub;
  bool _isFilterChipLoading = false;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      HomeScreen(scrollController: _homeScrollController),
      const CategoryScreen(),
      const SearchBarScreen(),
      const OrdersScreen(),
      const AccountScreen(),
    ];
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      final uid = user?.uid ?? '';
      _unreadCountStream = uid.isEmpty
          ? null
          : NotificationService().unreadCountStream(
              recipientId: uid,
              recipientRole: NotificationService.roleStudent,
            );
      if (mounted) setState(() {});
    });
    _homeScrollController.addListener(_onHomeScroll);
    _desktopSearchFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isDesktopSearchOpen = _desktopSearchFocusNode.hasFocus;
        });
      }
    });
  }

  void _onHomeScroll() {
    if (!mounted) return;
    final isScrolledNow =
        _homeScrollController.hasClients && _homeScrollController.offset > 5;
    if (isScrolledNow != _isScrolled) {
      setState(() {
        _isScrolled = isScrolledNow;
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _homeScrollController.removeListener(_onHomeScroll);
    _homeScrollController.dispose();
    _desktopSearchController.dispose();
    _desktopSearchFocusNode.dispose();
    super.dispose();
  }

  // Helper method to handle navigation choices
  void _onPageSelected(int index) {
    final bool isDesktop = isDesktopWidth(context);
    if (index == 2) {
      if (isDesktop) {
        // On desktop: open the inline Uber-Eats-style search overlay
        setState(() {
          _isDesktopSearchOpen = true;
        });
        Future.microtask(() => _desktopSearchFocusNode.requestFocus());
      } else {
        // On mobile: push the full search page
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SearchBarScreen()),
        );
      }
    } else {
      setState(() {
        currentPageIndex = index;
      });
    }
  }

  // --- Uber Eats / Deliveroo Style Web Desktop Top Navigation Header ---
  Widget _buildDesktopHeader(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : (user?.email?.split('@').first ?? 'Account');

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // 1. Logo (Clickable -> Home)
          InkWell(
            onTap: () => setState(() => currentPageIndex = 0),
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: AppLogo(),
            ),
          ),
          const SizedBox(width: 24),

          // 2. Uber Eats Style Interactive Search Input Bar in Header
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: _isDesktopSearchOpen
                    ? Colors.white
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _isDesktopSearchOpen
                      ? Colors.orange
                      : Colors.grey.shade300,
                  width: _isDesktopSearchOpen ? 2 : 1,
                ),
                boxShadow: _isDesktopSearchOpen
                    ? [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.orange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _desktopSearchController,
                        focusNode: _desktopSearchFocusNode,
                        onChanged: (q) {
                          setState(() {
                            _desktopSearchQuery = q;
                            _isDesktopSearchOpen = true;
                          });
                        },
                        onTap: () {
                          setState(() {
                            _isDesktopSearchOpen = true;
                          });
                        },
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: const InputDecoration(
                          hintText: "Search",
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    if (_desktopSearchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          _desktopSearchController.clear();
                          setState(() {
                            _desktopSearchQuery = '';
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),

          // 3. Quick Action Navigation Bar (Home, Categories, Orders, Notifications, Basket, Account)
          Row(
            children: [
              // Home Nav Link
              _buildHeaderNavLink(
                label: "Home",
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                index: 0,
              ),
              const SizedBox(width: 8),

              // Categories Nav Link
              _buildHeaderNavLink(
                label: "Categories",
                icon: Icons.category_outlined,
                selectedIcon: Icons.category,
                index: 1,
              ),
              const SizedBox(width: 8),

              // Orders Nav Link
              _buildHeaderNavLink(
                label: "Orders",
                icon: Icons.receipt_long_outlined,
                selectedIcon: Icons.receipt_long,
                index: 3,
              ),
              const SizedBox(width: 12),

              // Notifications Icon
              StreamBuilder<int>(
                stream: _unreadCountStream,
                builder: (context, snapshot) {
                  final unreadCount = snapshot.hasData ? snapshot.data! : 0;
                  return IconButton(
                    tooltip: 'Notifications',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationScreen(),
                        ),
                      );
                    },
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.notifications_outlined,
                          color: Colors.grey.shade800,
                          size: 22,
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: -3,
                            top: -3,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Color(0xFF2E7D32),
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 14,
                                minHeight: 14,
                              ),
                              child: Text(
                                unreadCount > 9 ? '9+' : '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),

              // Deliveroo / Uber Eats Basket Pill Button
              ListenableBuilder(
                listenable: CartService(),
                builder: (context, child) {
                  final cartItemsCount = CartService().totalItemsCount;
                  final totalAmount = CartService().totalAmount.toInt();
                  final hasCart = cartItemsCount > 0;

                  return InkWell(
                    onTap: () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (BuildContext context) {
                          return CartBottomSheet(
                            onOrderPlaced: () {
                              setState(() {
                                currentPageIndex = 3;
                              });
                            },
                          );
                        },
                      );
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: hasCart ? Colors.orange : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: hasCart
                            ? [
                                BoxShadow(
                                  color: Colors.orange.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shopping_basket_outlined,
                            size: 18,
                            color: hasCart ? Colors.white : Colors.black87,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            hasCart
                                ? '$cartItemsCount • TZS $totalAmount'
                                : 'Cart (0)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: hasCart ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),

              // Account Avatar Button
              InkWell(
                onTap: () => setState(() => currentPageIndex = 4),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: currentPageIndex == 4
                        ? Colors.orange.withValues(alpha: 0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: currentPageIndex == 4
                          ? Colors.orange
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.orange,
                        child: Text(
                          userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        userName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: currentPageIndex == 4
                              ? Colors.orange
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderNavLink({
    required String label,
    required IconData icon,
    required IconData selectedIcon,
    required int index,
  }) {
    final isSelected = currentPageIndex == index;
    return InkWell(
      onTap: () => _onPageSelected(index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.orange.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              size: 18,
              color: isSelected ? Colors.orange : Colors.grey.shade700,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.orange : Colors.grey.shade800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onFilterChipSelected(_FilterDescriptor descriptor) {
    if (_isFilterChipLoading) return;
    if (descriptor.section == 'all') {
      setState(() => currentPageIndex = 0);
      return;
    }

    _openFilteredItems(descriptor);
  }

  Future<void> _openFilteredItems(_FilterDescriptor descriptor) async {
    // Wait for the first menu snapshot when the cache has not loaded yet, so
    // we never navigate to CategoriesTitles with an empty fallback list.
    var allItems = FoodData.cachedFoodItems;
    if (allItems == null) {
      _isFilterChipLoading = true;
      try {
        allItems = await FoodData.foodItemsStream.first.timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {
        _isFilterChipLoading = false;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Menu is still loading. Please try again.'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      _isFilterChipLoading = false;
      if (!mounted) return;
    }

    final filtered = switch (descriptor.section) {
      'todays_deals' =>
        allItems.where((item) => item.section == 'todays_deals').toList(),
      'campus_favourite' =>
        allItems.where((item) => item.section == 'campus_favourite').toList(),
      'drinks' => allItems.where((item) => item.section == 'drinks').toList(),
      'other' => allItems.where((item) => item.section == 'other').toList(),
      'available' => allItems.where((item) => item.available).toList(),
      _ => allItems,
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoriesTitles(
          title: descriptor.title,
          items: filtered,
          heroTagPrefix: 'chip_${descriptor.title.replaceAll(' ', '_')}_',
        ),
      ),
    );
  }

  // --- Deliveroo Style Sub-Header Category Pills Strip for Desktop ---
  Widget _buildDesktopSubHeader() {
    return Container(
      height: 54,
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final descriptor in _filterDescriptors)
            _buildFilterChip(
              descriptor: descriptor,
              isSelected: descriptor.section == 'all' && currentPageIndex == 0,
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required _FilterDescriptor descriptor,
    required bool isSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10.0),
      child: InkWell(
        onTap: () => _onFilterChipSelected(descriptor),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.orange : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.orange : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                descriptor.icon,
                size: 16,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                descriptor.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Uber Eats Style Desktop Inline Search Dropdown Overlay ---
  Widget _buildDesktopSearchOverlay() {
    return StreamBuilder<List<FoodItem>>(
      stream: FoodData.foodItemsStream,
      builder: (context, snapshot) {
        final query = _desktopSearchQuery;
        final hasError = snapshot.hasError;
        final isLoading = !snapshot.hasData && !hasError;
        final allItems = snapshot.data ?? [];
        final searchResults = query.isEmpty
            ? <FoodItem>[]
            : allItems
                  .where(
                    (item) =>
                        item.title.toLowerCase().contains(
                          query.toLowerCase(),
                        ) ||
                        item.category.toLowerCase().contains(
                          query.toLowerCase(),
                        ) ||
                        item.displayCafe.toLowerCase().contains(
                          query.toLowerCase(),
                        ),
                  )
                  .take(10)
                  .toList();

        const topCategories = [
          {'icon': '🥞', 'label': 'Breakfast'},
          {'icon': '🍴', 'label': 'Lunch'},
          {'icon': '🥮', 'label': 'Dinner'},
          {'icon': '🍕', 'label': 'Teasers'},
          {'icon': '🥂', 'label': 'Drinks'},
        ];

        // Position the dropdown just below the header bar (72px header + 54px subheader)
        return Positioned(
          top: 72,
          left: 0,
          right: 0,
          child: Material(
            elevation: 12,
            shadowColor: Colors.black26,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 420),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: hasError
                  ? _buildSearchOverlayError(snapshot.error)
                  : isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(color: Colors.orange),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (query.isEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
                            child: Text(
                              'Top categories',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: topCategories.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 1,
                                indent: 20,
                                endIndent: 20,
                              ),
                              itemBuilder: (context, index) {
                                final cat = topCategories[index];
                                return ListTile(
                                  leading: Text(
                                    cat['icon']!,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                  title: Text(
                                    cat['label']!,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  onTap: () {
                                    final categoryName = cat['label']!;
                                    final catItems = allItems
                                        .where(
                                          (i) =>
                                              i.category.toLowerCase().contains(
                                                categoryName.toLowerCase(),
                                              ) ||
                                              i.title.toLowerCase().contains(
                                                categoryName.toLowerCase(),
                                              ) ||
                                              i.section.toLowerCase().contains(
                                                categoryName.toLowerCase(),
                                              ),
                                        )
                                        .toList();
                                    _desktopSearchFocusNode.unfocus();
                                    setState(() {
                                      _isDesktopSearchOpen = false;
                                    });
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CategoriesTitles(
                                          title: categoryName,
                                          items: catItems,
                                          heroTagPrefix: 'search_cat_',
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ] else ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                            child: Text(
                              'Results for "$_desktopSearchQuery" (${searchResults.length})',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          if (searchResults.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Center(
                                child: Text(
                                  'No food items found matching your search.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            )
                          else
                            Flexible(
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: searchResults.length,
                                itemBuilder: (context, index) {
                                  final item = searchResults[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: item.buildImage(
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    title: Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${item.displayCafe} • TZS ${item.price}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    trailing: Container(
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
                                        size: 16,
                                      ),
                                    ),
                                    onTap: () {
                                      _desktopSearchFocusNode.unfocus();
                                      setState(() {
                                        _isDesktopSearchOpen = false;
                                      });
                                      FoodDetailsScreen.open(
                                        context,
                                        item,
                                        heroTagPrefix: 'search_overlay_',
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchOverlayError(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 36, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Failed to load the menu.',
              style: TextStyle(color: Colors.black87, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '$error',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = isDesktopWidth(context);

    final Widget desktopBody = Column(
      children: [
        // --- TOP DESKTOP HEADER (Uber Eats / Deliveroo Bar) ---
        _buildDesktopHeader(context),

        // --- SUB-HEADER CATEGORY STRIP ---
        _buildDesktopSubHeader(),
        const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),

        // --- MAIN WEB CANVAS & PERSISTENT BASKET ---
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main Content Canvas
              Expanded(
                child: Container(
                  color: Colors.grey.shade50,
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: _pages[currentPageIndex],
                  ),
                ),
              ),

              // Right Sidebar: Persistent Deliveroo-Style Cart Summary
              ListenableBuilder(
                listenable: CartService(),
                builder: (context, child) {
                  final cartItemsCount = CartService().totalItemsCount;
                  if (cartItemsCount == 0) return const SizedBox.shrink();

                  return Container(
                    width: 360,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        left: BorderSide(
                          color: Colors.grey.shade200,
                          width: 1.5,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(-4, 0),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: CartBottomSheet(
                        onOrderPlaced: () {
                          setState(() {
                            currentPageIndex = 3;
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );

    return DashNoInterNetScreen(
      image: Image.asset("designs/assets/satellite.png", width: 90, height: 90),
      titleText: "Sorry for the delay",
      titleTextStyle: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Colors.black,
      ),
      subtitleText:
          "We're having trouble connecting, but you should have your food shortly.",
      subtitleTextStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.normal,
        color: Colors.black54,
      ),
      backgroundColor: Colors.white,
      padding: const EdgeInsets.all(16.0),
      textAlign: TextAlign.center,
      spacing: 15,
      buttonTextColor: Colors.white,
      buttonColor: Colors.grey,
      buttonPadding: const EdgeInsets.symmetric(
        horizontal: 18.0,
        vertical: 8.0,
      ),
      buttonText: "Try Again",
      buttonTextStyle: const TextStyle(
        fontSize: 16,
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
      buttonBorderShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      buttonHeight: 50,
      buttonWidth: 250,
      buttonStyle: ElevatedButton.styleFrom(
        elevation: 4,
        backgroundColor: Colors.orange,
      ),
      // Re-verify connectivity so SyncQueueService triggers queue processing
      // with the real platform result, not a UI-asserted value.
      onInternetAvailable: () {
        ConnectivityService().checkConnectivity();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Internet connected!")));
      },
      onRetryFailed: () {
        ConnectivityService().checkConnectivity();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "no internet found! please connect to internet and try again.",
            ),
          ),
        );
      },
      child: Scaffold(
        // Top Bar — Visible only on mobile
        appBar: isDesktop
            ? null
            : AppBar(
                toolbarHeight: 50,
                backgroundColor: (currentPageIndex == 0 && !_isScrolled)
                    ? Colors.orange
                    : Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                surfaceTintColor: Colors.transparent,
                iconTheme: const IconThemeData(color: Colors.black87),
                title: const AppLogo(),
                actions: <Widget>[
                  // Notifications Icon
                  StreamBuilder<int>(
                    stream: _unreadCountStream,
                    builder: (context, snapshot) {
                      final unreadCount = snapshot.hasData ? snapshot.data! : 0;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          IconButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const NotificationScreen(),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.notifications_outlined,
                              semanticLabel: 'notification bell',
                            ),
                          ),
                          if (unreadCount > 0)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2E7D32),
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  unreadCount > 9 ? '9+' : '$unreadCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  // Cart Icon
                  ListenableBuilder(
                    listenable: CartService(),
                    builder: (context, child) {
                      final cartItemsCount = CartService().totalItemsCount;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          IconButton(
                            onPressed: () {
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                showDragHandle: true,
                                builder: (BuildContext context) {
                                  return CartBottomSheet(
                                    onOrderPlaced: () {
                                      setState(() {
                                        currentPageIndex = 3;
                                      });
                                    },
                                  );
                                },
                              );
                            },
                            icon: const Icon(
                              Icons.shopping_cart_outlined,
                              semanticLabel: 'cart',
                            ),
                          ),
                          if (cartItemsCount > 0)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  '$cartItemsCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),

        // Yellow floating basket button — visible only on mobile when cart has items
        floatingActionButton: isDesktop
            ? null
            : CartFab(
                onOrderPlaced: () {
                  setState(() {
                    currentPageIndex = 3;
                  });
                },
              ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,

        // Responsive Body — Uber Eats & Deliveroo Web Layout for PC View
        body: isDesktop
            ? Stack(
                children: [
                  desktopBody,

                  if (_isDesktopSearchOpen) ...[
                    // Backdrop detector to close search overlay on click outside
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          _desktopSearchFocusNode.unfocus();
                          setState(() {
                            _isDesktopSearchOpen = false;
                          });
                        },
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                    ),

                    // Expandable search dropdown menu
                    _buildDesktopSearchOverlay(),
                  ],
                ],
              )
            : Stack(
                children: [
                  _pages[currentPageIndex],
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: OfflineBanner(),
                  ),
                ],
              ),

        // Bottom Navigation Bar — Visible only on mobile
        bottomNavigationBar: isDesktop
            ? null
            : NavigationBar(
                selectedIndex: currentPageIndex,
                onDestinationSelected: _onPageSelected,
                indicatorColor: Colors.orange,

                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined, semanticLabel: 'home'),
                    label: "Home",
                  ),
                  NavigationDestination(
                    icon: Icon(
                      Icons.category_outlined,
                      semanticLabel: 'categories',
                    ),
                    label: "Categories",
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.search, semanticLabel: 'search food'),
                    label: "Search",
                  ),
                  NavigationDestination(
                    icon: Icon(
                      Icons.receipt_long_outlined,
                      semanticLabel: 'my orders',
                    ),
                    label: "Orders",
                  ),
                  NavigationDestination(
                    icon: Icon(
                      Icons.person_outlined,
                      semanticLabel: 'my profile',
                    ),
                    label: "Account",
                  ),
                ],
              ),
      ),
    );
  }
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('designs/assets/logo.png', width: 40, height: 40),
        const SizedBox(width: 8),
        const Text(
          'Campus Bite',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
