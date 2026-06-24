import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/account_screen.dart';
import '../screens/category_screen.dart';
import '../screens/order_screen.dart';
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

  final List<Widget> _pages = [
    const HomeScreen(),
    const CategoryScreen(),
    const OrdersScreen(),
    // This is the Account screen from account_screen.dart
    const AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return DashNoInterNetScreen(
      image: Image.asset("designs/assets/satellite.png", height: 80, width: 90),
      titleText: "Oops !",
      titleTextStyle: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Colors.black,
      ),
      subtitleText:
          "No Internet Connection Found. Check your connection and start again.",
      subtitleTextStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.normal,
        color: Colors.black54,
      ),
      backgroundColor: Colors.white,
      padding: const EdgeInsets.all(16.0),
      textAlign: TextAlign.center,
      spacing: 15,
      child: Scaffold(
        // TopBar
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('designs/assets/logo.png', width: 40, height: 40),
              Text(
                'CampusBite',
                style: TextStyle(
                  color: Color.fromARGB(255, 0, 118, 37),
                  letterSpacing: .5,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          // notification icon- its screen can be found in account_screen.dart file
          actions: <Widget>[
            IconButton(
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
        body: _pages[currentPageIndex],

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
          onDestinationSelected: (int index) {
            /* if (index == 3){
          Navigator.push(context,
          MaterialPageRoute(builder: (_) => AboutScreen()));
          }*/
            setState(() {
              currentPageIndex = index;
            });
          },
          indicatorColor: Colors.orange,
          selectedIndex: currentPageIndex,
          destinations: [
            NavigationDestination(
              icon: const Icon(CupertinoIcons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: const Icon(CupertinoIcons.square_stack_3d_up),
              label: 'Categories',
            ),
            NavigationDestination(
              icon: const Icon(CupertinoIcons.cube_box),
              label: 'Orders',
            ),
            NavigationDestination(
              icon: const Icon(CupertinoIcons.person),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}
