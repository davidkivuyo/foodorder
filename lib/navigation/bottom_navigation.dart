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
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('designs/assets/logo.png', width: 40, height: 40),
              Text(
                'CampusBite',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          // notification icon- its screen can be found in account_screen.dart file
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
        extendBody: true,
        body: _pages[currentPageIndex],

        // shopping cart icon
        /*floatingActionButton: FloatingActionButton(
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
        ),*/

        // bottom navigation bar
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(30),
              topLeft: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.2),
                spreadRadius: 2,
                blurRadius: 5,
                offset: Offset(0, 3),
              ),
            ],
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey.shade200, width: 1.0),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavButton(
                  icon: CupertinoIcons.home,
                  isSelected: currentPageIndex == 0,
                  onTap: () => setState(() => currentPageIndex = 0),
                ),
                _buildNavButton(
                  icon: CupertinoIcons.layers_alt,
                  isSelected: currentPageIndex == 1,
                  onTap: () => setState(() => currentPageIndex = 1),
                ),
                _buildNavButton(
                  icon: CupertinoIcons.cube_box,
                  isSelected: currentPageIndex == 2,
                  onTap: () => setState(() => currentPageIndex = 2),
                ),
                _buildNavButton(
                  icon: CupertinoIcons.person,
                  isSelected: currentPageIndex == 3,
                  onTap: () => setState(() => currentPageIndex = 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // If selected: solid black. If unselected: slightly gray background.
          color: isSelected ? Colors.white : Colors.white,
          // Adds a thin border only when the icon is NOT selected
          border: isSelected
              ? Border.all(color: Colors.grey.shade300, width: 1.0)
              : null,
        ),
        child: Icon(
          icon,
          // If selected: white icon. If unselected: dark grey/black icon.
          color: isSelected ? Colors.black : Colors.black87,
          size: 24, // Slightly reduced to fit nicely inside the bordered circle
        ),
      ),
    );
  }
}
