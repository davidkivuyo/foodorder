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
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/home_screen.dart';
import '../screens/account_screen.dart';
import '../screens/category_screen.dart';
import '../screens/order_screen.dart';
import '../data/search_bar.dart';
import 'package:dash_no_internet_screen/dash_no_internet_screen.dart';
import '../services/cart_service.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';
import '../widgets/cart_bottom_sheet.dart';
import '../widgets/cart_fab.dart';
import '../widgets/offline_banner.dart';

// home screen
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _NavigationExampleState();
}

class _NavigationExampleState extends State<MainScreen> {
  int currentPageIndex = 0;
  final ScrollController _homeScrollController = ScrollController();
  bool _isScrolled = false;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _homeScrollController.addListener(_onScroll);
    // Built once so setState for _isScrolled never recreates widget instances.
    _pages = [
      HomeScreen(scrollController: _homeScrollController),
      const CategoryScreen(),
      const SearchBarScreen(),
      const OrdersScreen(),
      const AccountScreen(),
    ];
  }

  void _onScroll() {
    if (_homeScrollController.hasClients) {
      final scrolled = _homeScrollController.offset > 10;
      if (scrolled != _isScrolled) {
        setState(() {
          _isScrolled = scrolled;
        });
      }
    }
  }

  @override
  void dispose() {
    _homeScrollController.removeListener(_onScroll);
    _homeScrollController.dispose();
    super.dispose();
  }

  // Helper method to handle navigation choices
  void _onPageSelected(int index) {
    if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SearchBarScreen()),
      );
    } else {
      setState(() {
        currentPageIndex = index;
      });
    }
  }

  // Sidebar item widget with hover/active styling for desktop
  Widget _buildSidebarItem({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required int index,
  }) {
    final isSelected = currentPageIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: InkWell(
        onTap: () => _onPageSelected(index),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.orange.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? selectedIcon : icon,
                color: isSelected ? Colors.orange : Colors.grey.shade700,
                size: 22,
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.orange : Colors.grey.shade800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 850;

    return DashNoInterNetScreen(
      image: Image.asset("designs/assets/satellite.png", width: 90, height: 90),
      titleText: "Sorry for the delay",
      titleTextStyle: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Colors.black,
      ),
      subtitleText:
          "We're having trouble connecting, but you should have your food very soon.",
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
      buttonColor: Colors.orange,
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
        extendBodyBehindAppBar: true,
        // Top Bar — Visible only on mobile
        appBar: isDesktop
            ? null
            : AppBar(
                backgroundColor: _isScrolled
                    ? (Theme.of(context).appBarTheme.backgroundColor ??
                          Colors.grey.shade100)
                    : Colors.transparent,
                surfaceTintColor: _isScrolled
                    ? (Theme.of(context).appBarTheme.surfaceTintColor ??
                          Colors.grey.shade100)
                    : Colors.transparent,
                elevation: _isScrolled ? 2 : 0,
                scrolledUnderElevation: 2,
                toolbarHeight: 50,
                title: const AppLogo(),
                actions: <Widget>[
                  // Notifications Icon
                  StreamBuilder<int>(
                    stream: NotificationService().unreadCountStream(
                      recipientId: FirebaseAuth.instance.currentUser?.uid ?? '',
                      recipientRole: NotificationService.roleStudent,
                    ),
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
                              Icons.notifications,
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
                              Icons.shopping_cart,
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

        // Responsive Body
        body: isDesktop
            ? Row(
                children: [
                  // --- LEFT SIDEBAR (Desktop Menu) ---
                  Container(
                    width: 250,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        right: BorderSide(
                          color: Colors.grey.shade200,
                          width: 1.5,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 30.0,
                          ),
                          child: AppLogo(),
                        ),
                        const SizedBox(height: 8),
                        _buildSidebarItem(
                          icon: Icons.home_outlined,
                          selectedIcon: Icons.home,
                          label: "Home",
                          index: 0,
                        ),
                        _buildSidebarItem(
                          icon: Icons.category_outlined,
                          selectedIcon: Icons.category,
                          label: "Categories",
                          index: 1,
                        ),
                        _buildSidebarItem(
                          icon: Icons.search_outlined,
                          selectedIcon: Icons.search,
                          label: "Search",
                          index: 2,
                        ),
                        _buildSidebarItem(
                          icon: Icons.receipt_long_outlined,
                          selectedIcon: Icons.receipt_long,
                          label: "Orders",
                          index: 3,
                        ),
                        _buildSidebarItem(
                          icon: Icons.person_outlined,
                          selectedIcon: Icons.person,
                          label: "Account",
                          index: 4,
                        ),
                        const Spacer(),
                        // Desktop Notification summary button
                        StreamBuilder<int>(
                          stream: NotificationService().unreadCountStream(
                            recipientId:
                                FirebaseAuth.instance.currentUser?.uid ?? '',
                            recipientRole: NotificationService.roleStudent,
                          ),
                          builder: (context, snapshot) {
                            final unreadCount = snapshot.hasData
                                ? snapshot.data!
                                : 0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 8.0,
                              ),
                              child: TextButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const NotificationScreen(),
                                    ),
                                  );
                                },
                                icon: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Icon(
                                      Icons.notifications_outlined,
                                      color: Colors.grey.shade700,
                                    ),
                                    if (unreadCount > 0)
                                      Positioned(
                                        right: -4,
                                        top: -4,
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
                                            unreadCount > 9
                                                ? '9+'
                                                : '$unreadCount',
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
                                label: Text(
                                  "Notifications",
                                  style: TextStyle(
                                    color: Colors.grey.shade800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),

                  // --- CENTER CANVAS (Constrained Screen Content) ---
                  Expanded(
                    child: Container(
                      color: Colors.grey.shade50,
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: _pages[currentPageIndex],
                      ),
                    ),
                  ),

                  // --- RIGHT SIDEBAR (Desktop Persistent Cart) ---
                  ListenableBuilder(
                    listenable: CartService(),
                    builder: (context, child) {
                      final cartItemsCount = CartService().totalItemsCount;
                      if (cartItemsCount == 0) return const SizedBox.shrink();

                      return Container(
                        width: 340,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            left: BorderSide(
                              color: Colors.grey.shade200,
                              width: 1.5,
                            ),
                          ),
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
              )
            : Stack(
                children: [
                  IndexedStack(index: currentPageIndex, children: _pages),
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
                //labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
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
        const Text(
          'Campus Bite',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
