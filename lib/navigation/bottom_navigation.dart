import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/account_screen.dart';


// home screen
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _NavigationExampleState();
}

// The top appbar
class CustomBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
          margin: const EdgeInsets.only(top: 12.0, left: 8.0, right: 8.0),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CampusBite',
                    style: TextStyle(
                    color: Color.fromARGB(255, 1, 167, 53),
                    letterSpacing: .5,
                    fontSize: 20,
                    fontStyle: FontStyle.normal,
                  ),
                ),
              IconButton(onPressed: () { 
            Navigator.push(
              context, 
              MaterialPageRoute(
                builder: (_) => Notify(),
                ),
                );
                }, icon: Icon(Icons.notifications)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(60.0);
}


// notification screen
class Notify extends StatelessWidget {
  const Notify({super.key});

  @override
  Widget build(BuildContext context) {
   return Scaffold(
      appBar: AppBar(title: Text('Notifications'),),
    );
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
      appBar: CustomBar(),

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