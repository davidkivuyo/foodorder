import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/account_screen.dart';
import '../screens/category_screen.dart';
import '../screens/order_screen.dart';
import '../data/search_bar.dart';
import 'package:dash_no_internet_screen/dash_no_internet_screen.dart';

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
              padding: const EdgeInsets.only(right: 10),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => Notify()),
                );
              },
              icon: const Icon(CupertinoIcons.bell),
            ),
          ],
        ),

        // body
        body: IndexedStack(index: currentPageIndex, children: _pages),

        // shopping cart icon
        floatingActionButton: FloatingActionButton(
          tooltip: 'Cart',
          backgroundColor: Colors.orange,
          shape: CircleBorder(),
          onPressed: () {
            //Drag handle
            showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (BuildContext context) {
                return SizedBox(
                  height: 140,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: .center,
                      mainAxisSize: .min,
                      children: <Widget>[
                        const Text('You have an empty cart'),
                        const SizedBox(height: 10),
                        Icon(Icons.hourglass_empty),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          child: const Icon(CupertinoIcons.cart),
        ),

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

          indicatorColor: Colors.transparent,

          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          destinations: [
            NavigationDestination(
              icon: Icon(CupertinoIcons.home),
              label: "Home",
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.layers),
              label: "Categories",
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.search),

              label: "Search",
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.archivebox),
              label: "Orders",
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.person_circle),
              label: "Profile",
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
          'CampusBite',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
