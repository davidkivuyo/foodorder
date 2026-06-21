import 'package:flutter/material.dart';

String firstname = 'DAVID';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
 return Scaffold(

  // home screen body
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
                    color: Colors.orange,
                    letterSpacing: .25,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                     ),
                  ),
                  Text(
                    "What's your bite today?",
                    style: TextStyle(
                    color: Color.fromARGB(255, 138, 83, 0),
                    letterSpacing: .25,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  ),
const SizedBox(height: 24),
                  // search bar
                   Container(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 214, 214, 214),
                      borderRadius: BorderRadius.circular(16)
                    ),
                  child: const TextField(
                    decoration: InputDecoration(
                    hintText: 'Search foods, snacks and drinks',
                    border: InputBorder.none,
                    icon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
 );

  }
}
