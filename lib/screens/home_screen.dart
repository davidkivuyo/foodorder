import 'package:flutter/material.dart';

String firstname = 'DAVID';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
 return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  Text(
                     'Hello $firstname',
                     style: TextStyle(
                    color: Color.fromARGB(255, 218, 131, 0),
                    letterSpacing: .5,
                    fontSize: 20,
                    fontStyle: FontStyle.normal,
                     ),
                  ),
                   Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SearchBar(
                    leading: Icon(Icons.search),
                    hintText: 'Search',
                  )
                ),
              ],
            ),
          ),
        ),
      ),
 );

  }
}
