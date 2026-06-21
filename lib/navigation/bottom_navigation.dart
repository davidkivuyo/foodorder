import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/account_screen.dart';

// home screen
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _NavigationExampleState();
}

// notification screen
class Notify extends StatelessWidget {
  const Notify({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: Text('Notifications')));
  }
}

// body and bottom navigation
class _NavigationExampleState extends State<MainScreen> {
  int currentPageIndex = 0;

  final List<Widget> _pages = [
    const HomeScreen(),
    const Center(child: Text('Categories Content')),
    const Center(child: Text('Order Content')),
    const AccountScreen(), // This is your Account screen
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => Notify()),
              );
            },
            icon: Icon(Icons.notifications_outlined),
          ),
        ],
        elevation: 0,
      ),

      // body
      body: _pages[currentPageIndex],

      // shopping cart icon
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.orange,
        shape: CircleBorder(),
        onPressed: () {
          print("pressed");
        },
        child: Icon(Icons.shopping_cart_outlined),
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
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            label: 'Categories',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
