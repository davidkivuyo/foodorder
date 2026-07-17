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
import 'package:go_router/go_router.dart';
import '../services/fcm_service.dart';
import '../services/notification_service.dart';
import '../widgets/cart_bottom_sheet.dart';
import '../widgets/cart_fab.dart';

/// Maps deep link paths to bottom navigation tab indices.
/// Returns the index for the bottom nav bar, or null for unknown paths.
int? deepLinkToTabIndex(String deepLink) {
  if (deepLink == '/account' ||
      deepLink == '/strike-history') {
    return 4; // Account tab
  }
  if (deepLink == '/orders' || deepLink.startsWith('/orders/')) {
    return 3; // Orders tab
  }
  if (deepLink == '/notifications') {
    return null; // Notifications is a separate screen, not a tab
  }
  return 0; // Default: Home tab
}

// home screen
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _NavigationExampleState();
}

// body and bottom navigation
class _NavigationExampleState extends State<MainScreen> {
  int currentPageIndex = 0;

  //─ FCM foreground notification banner ───────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Check for deep link tab from GoRouter query parameter
    _processDeepLinkQueryParam();

    // Set up the foreground notification banner callback.
    // MainScreen is wrapped in a Scaffold, so ScaffoldMessenger is available.
    FcmService.onForegroundNotification = _showInAppBanner;
  }

  void _processDeepLinkQueryParam() {
    // When navigated via a deep link, GoRouter adds a 'tab' query parameter.
    // This allows FCM notification taps to open the correct tab.
    try {
      final uri = GoRouterState.of(context).uri;
      final tabParam = uri.queryParameters['tab'];
      if (tabParam != null && tabParam.isNotEmpty) {
        final tabIndex = int.tryParse(tabParam);
        if (tabIndex != null && tabIndex >= 0 && tabIndex <= 4) {
          currentPageIndex = tabIndex;
        }
      }
    } catch (_) {
      // If GoRouterState isn't available (e.g., testing), ignore.
    }
  }

  @override
  void dispose() {
    // Clear the callback to avoid stale references
    FcmService.onForegroundNotification = null;
    super.dispose();
  }

  void _showInAppBanner({required String title, required String body}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              body,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
  static const List<Widget> _pages = [
    HomeScreen(),
    CategoryScreen(),
    SearchBarScreen(),
    OrdersScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
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
      onInternetAvailable: () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Internet connected!")));
      },
      onRetryFailed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "no internet found! please connect to internet and try again.",
            ),
          ),
        );
      },
      child: Scaffold(
        // TopBar
        appBar: AppBar(
          toolbarHeight: 50,
          title: const AppLogo(),

          // notification icon with live unread badge
          actions: <Widget>[
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
                                  currentPageIndex =
                                      3; // Navigate to Orders Screen (index 3)
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

        // Yellow floating basket button — visible only when cart has items
        floatingActionButton: CartFab(
          onOrderPlaced: () {
            setState(() {
              currentPageIndex = 3;
            });
          },
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,

        // body
        body: _pages[currentPageIndex],

        // bottom navigation bar
        bottomNavigationBar: NavigationBar(
          selectedIndex: currentPageIndex,
          onDestinationSelected: (index) {
            if (index == 2) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SearchBarScreen(),
                ),
              );
            } else {
              // For all other tabs, switch the index normally
              setState(() {
                currentPageIndex = index;
              });
            }
          },

          indicatorColor: Colors.orange,

          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, semanticLabel: 'home'),
              label: "Home",
            ),
            NavigationDestination(
              icon: Icon(Icons.category_outlined, semanticLabel: 'categories'),
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
              icon: Icon(Icons.person_outlined, semanticLabel: 'my profile'),
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
        Text(
          'Campus Bite',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
