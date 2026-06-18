import 'package:flutter/material.dart';
// import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Food order app',
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _NavigationExampleState();
}

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
                'CampusBite',style: TextStyle(
                    color: Color.fromARGB(255, 1, 167, 53),
                    letterSpacing: .5,
                    fontSize: 20,
                    fontStyle: FontStyle.normal,
                  ),
                ),
              IconButton(onPressed: () {}, icon: Icon(Icons.notifications)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(60.0);
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Account'));
  }
}

class _NavigationExampleState extends State<HomeScreen> {
  int currentPageIndex = 0;

  final List<Widget> _pages = [
    const Center(child: Text('Home Page Content')),
    const Center(child: Text('Categories Content')),
    const Center(child: Text('Order Content')),
    const AboutScreen(), // This is your Account screen
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appbar
      appBar: const CustomBar(),

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
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),

          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            label: 'Categories',
          ),
          NavigationDestination(
            icon: Badge(label: Text('999+'), child: Icon(Icons.receipt_long)),
            label: 'Order',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
