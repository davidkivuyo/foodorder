import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/account_screen.dart';


// home screen
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _NavigationExampleState();
}

class _NavigationExampleState extends State<HomeScreen> {
  int currentPageIndex = 0;

  final List<Widget> _pages = [
    const CustomBar(),
    const Center(child: Text('Categories Content')),
    const Center(child: Text('Order Content')),
    const AccountScreen(), // This is your Account screen
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      
      // body
      body: _pages[currentPageIndex],
      /*body: Center(
        child: ElevatedButton(
          child: Text('Account'),
          onPressed: () { 
            Navigator.push(
              context, 
              MaterialPageRoute(
                builder: (_) => AboutScreen(),
                ),
                );
                },
        ),),*/

      // shopping cart icon
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.shopping_cart),
        onPressed: () {
          print("pressed");
        },
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
            icon: Icon(Icons.home_outlined),            
            label: 'Home',
            ),
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