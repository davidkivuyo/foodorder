import 'package:flutter/material.dart';


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
