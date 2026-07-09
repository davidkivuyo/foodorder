import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/account_screen.dart';
import '../screens/category_screen.dart';
import '../screens/order_screen.dart';
import '../data/search_bar.dart';
import 'package:dash_no_internet_screen/dash_no_internet_screen.dart';
import '../services/cart_service.dart';
import '../widgets/cart_bottom_sheet.dart';
import '../widgets/cart_fab.dart';

// home screen
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _NavigationExampleState();
}

// body and bottom navigation
class _NavigationExampleState extends State<MainScreen> {
  int currentPageIndex = 0;

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

          // notification icon, its screen can be found in account_screen.dart file
          actions: <Widget>[
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => Notify()),
                );
              },
              icon: const Icon(
                Icons.notifications_outlined,
                semanticLabel: 'notification bell',
              ),
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
