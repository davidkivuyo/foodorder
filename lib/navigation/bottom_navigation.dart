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
      appBar: AppBar(
         title: Text(
                'CampusBite',
                    style: TextStyle(
                    color: Color.fromARGB(255, 1, 167, 53),
                    letterSpacing: .5,
                    fontSize: 20,
                    fontStyle: FontStyle.normal,
                  ),
                ),
              actions: <Widget>[
                IconButton(onPressed: () { 
            Navigator.push(
              context, 
              MaterialPageRoute(
                builder: (_) => Notify(),
                ),
                );
                }, 
                icon: Icon(Icons.notifications)
                ),
              ]
            
      ),

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