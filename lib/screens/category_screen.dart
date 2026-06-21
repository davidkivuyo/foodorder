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
                    style: TextStyle(fontSize: 22, color: Colors.black,fontWeight: FontWeight(600),letterSpacing: .75,),
                  ),
                  Text(
                    'Find the best meal for your study break!',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 18),
                categories(),


                 ],
              ),
            ),
        );
  }
}

Widget categories() {
  // Define categories and simulate 'Breakfast' being the active one
  final List<String> categoryList = ['Breakfast', 'Lunch', 'Dinner','Snacks', 'Drinks'];
  final String selectedCategory = 'Breakfast';

  return SizedBox(
    height: 45,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: categoryList.length,
      itemBuilder: (context, index) {
        final category = categoryList[index];
        final isSelected = category == selectedCategory;

        return Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFF5820D) : Colors.white,
              borderRadius: BorderRadius.circular(25), 
              border: isSelected 
                  ? null 
                  : Border.all(color: const Color.fromARGB(255, 237, 237, 237), width: 1.5),
            ),
            child: Center(
              child: Text(
                category,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color.fromARGB(255, 61, 61, 61),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}