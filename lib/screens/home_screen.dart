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
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  Text(
                    'Welcome $firstname!',
                    style: TextStyle(
                    color: Color.fromARGB(255, 218, 131, 0),
                    letterSpacing: .25,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                     ),
                  ),
                  Text(
                    'Whats your Bite today?',
                    style: TextStyle(
                    color: Color.fromARGB(255, 138, 83, 0),
                    letterSpacing: .25,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  ),
                   Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                  child: SearchBar(
                    leading: Icon(Icons.search),
                    hintText: 'Search foods, snacks and drinks',
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
