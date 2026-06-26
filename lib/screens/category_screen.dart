import 'package:flutter/material.dart';
import '../data/food_data.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  @override
  Widget build(BuildContext context) {
    // Allows scrolling
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Explore Categories',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: .75,
              ),
            ),
            Text(
              'Find the best meal for your study break!',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 18),
            categories(),

            const SizedBox(height: 18),
            Cards(),

            const SizedBox(height: 10),
            BottomBanner(),
          ],
        ),
      ),
    );
  }
}

Widget categories() {
  final List<String> categoryList = [
    '🥞 Breakfast',
    '🍴 Lunch',
    '🥮 Dinner',
    '🍫 Snacks',
    '🥂 Drinks',
  ];
  final String selectedCategory = '🍴 Lunch';

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
    final List<FoodItem> menuItems = [
      const FoodItem(
        image: 'designs/assets/sandwich.jpg',
        title: 'Honey Sandwich',
        subtitle: 'Fresh sandwich for your breakfast',
        price: 'Tsh 1000',
        rating: 4.5,
        category: 'Breakfast',
      ),
      const FoodItem(
        image: 'designs/assets/burgerchips.jpg',
        title: 'Burger with Fries',
        subtitle: 'Served with your favourite additive',
        price: 'Tsh 7000',
        rating: 4.8,
        category: 'Lunch',
      ),
      const FoodItem(
        image: 'designs/assets/biriyanimeat.jpg',
        title: 'Biriyani meat',
        subtitle: 'Loaded with fresh vegetables',
        price: 'Tsh 4500',
        rating: 4.3,
        category: 'Lunch',
      ),
      const FoodItem(
        image: 'designs/assets/chips.jpg',
        title: 'Chips Mshkaki',
        subtitle: 'Extra cheese and crispy fries',
        price: 'Tsh 8500',
        rating: 4.9,
        category: 'Dinner',
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: menuItems.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        return FoodCard(item: menuItems[index]);
      },
    );
  }
}

class FoodCard extends StatelessWidget {
  final FoodItem item;

  const FoodCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              item.image,
              height: 120,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),

          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.price,
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BottomBanner extends StatelessWidget {
  const BottomBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          // Matching the dark green shade from the design
          color: const Color(0xFF0F6322),

          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            // Content Layout
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Flash Deal Tag
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFFF5820D,
                    ), // Match your main orange color
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'FLASH DEAL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Main Heading
                const Text(
                  'Late Night Munchies',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                // Subtitle
                Text(
                  '30% off after 9 PM',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            // Positioned Party Popper Icon on the top-right
            Positioned(
              top: 0,
              right: 0,

              child: Icon(
                Icons.celebration, // Using celebration icon as the party popper
                size: 40,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
