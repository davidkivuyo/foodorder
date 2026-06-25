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
              style: TextStyle(
                fontSize: 22,
                color: Colors.black,
                fontWeight: FontWeight(600),
                letterSpacing: .75,
              ),
            ),
            Text(
              'Find the best meal for your study break!',
              style: TextStyle(fontSize: 15, color: Colors.black),
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
  final List<String> categoryList = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snacks',
    'Drinks',
  ];
  final String selectedCategory = 'Launch';

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
                  : Border.all(
                      color: const Color.fromARGB(255, 237, 237, 237),
                      width: 1.5,
                    ),
            ),
            child: Center(
              child: Text(
                category,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : const Color.fromARGB(255, 61, 61, 61),
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

class Cards extends StatelessWidget {
  const Cards({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // categories food cards
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 0,
                  color: Colors.transparent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Food Image
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Card Details
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'title',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black,
                              ),
                            ),
                            Text(
                              'subtitle',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '4.5', // Replace with your actual rating map key
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                Icon(
                                  Icons.star_rounded,
                                  color: Colors.amber,
                                  size: 16,
                                ),
                              ],
                            ),

                            const SizedBox(height: 2),

                            // Price and Add Button Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'price',
                                  style: const TextStyle(
                                    color: Color(0xFF0F5132), // Dark green tone
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    color: Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
