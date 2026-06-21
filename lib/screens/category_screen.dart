import 'package:flutter/material.dart';

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    
    // Allows scrolling
    return SingleChildScrollView(
     child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  Text(
                    'Explore Categories',
                    style: TextStyle(fontSize: 18, color: Colors.black),
                  ),
                  Text(
                    'Find the best meal for your study break!',
                    style: TextStyle(
                      fontSize: 13,
                      color: const Color.fromARGB(255, 61, 60, 60),
                    ),
                  ),
                ],
              ),
             

            ),
          
          
        );
      
  }
}
