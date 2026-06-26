import 'package:flutter/material.dart';
import '../data/food_data.dart';
import '../data/search_bar.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<FoodItem> cafe1Menu = [
      FoodItem(
        image: 'designs/assets/ricemeat.jpg',
        title: 'Wali Nyama',
        subtitle: 'Fresh for your appetite',
        price: 2500,
        rating: 4.5,
        category: '',
      ),
      FoodItem(
        image: 'designs/assets/grilled-meat.jpg',
        title: 'Smoked grilled meat',
        subtitle: 'Fresh Steak out of the gill',
        price: 18000,
        rating: 4.8,
        category: '',
      ),
      FoodItem(
        image: 'designs/assets/chips.jpg',
        title: 'Chips Mshkaki',
        subtitle: 'Served with additives',
        price: 3000,
        rating: 4.3,
        category: '',
      ),
    ];

    final List<FoodItem> cafe2Menu = [
      FoodItem(
        image: 'designs/assets/sandwich.jpg',
        title: 'Honey Sandwich',
        subtitle: 'Fresh breakfast choice',
        price: 1000,
        rating: 4,
        category: '',
      ),
      FoodItem(
        image: 'designs/assets/burgerchips.jpg',
        title: 'Burger with fries',
        subtitle: 'Served warm and fast',
        price: 7000,
        rating: 3.9,
        category: '',
      ),
      FoodItem(
        image: 'designs/assets/biriyanimeat.jpg',
        title: 'Biriyani With meat',
        subtitle: 'Full plate satisfaction',
        price: 2500,
        rating: 4.7,
        category: '',
      ),
    ];

    return Scaffold(
      // home screen body
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // search bar
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TextField(
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'Search your next meal',
                      hintStyle: TextStyle(fontSize: 15),
                      fillColor: Colors.white,
                      border: InputBorder.none,
                      icon: Icon(Icons.search),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (BuildContext context) => SearchBarScreen(),
                        ),
                      );
                    },
                  ),
                ),

                //space
                const SizedBox(height: 18),

                // banner
                SpecialBannerCard(),

                // space
                const SizedBox(height: 18),

                // card grid for cafe 1
                CardRowItems(
                  title: "Today's Menu: CAFE 1",
                  items: cafe1Menu,
                  maxItems: 4,
                ),
                const Divider(),

                // card grid for cafe 2
                CardRowItems(
                  title: "Today's Menu: CAFE 2",
                  items: cafe2Menu,
                  maxItems: 4,
                ),
                const Divider(),

                Text(
                  "Quick Bites",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                QuickBites(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SpecialBannerCard extends StatelessWidget {
  // Constructor
  const SpecialBannerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),

          image: const DecorationImage(
            image: AssetImage('designs/assets/banner-rice.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            // Dark gradient overlay matching modern Flutter syntax
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.75), // Darker on the left
                    Colors.black.withValues(alpha: 0.1), // Clearer on the right
                  ],
                ),
              ),
            ),

            // Explicitly Positioned Fill layout to guarantee visibility of content
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Orange "TODAY'S SPECIAL" Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "TODAY'S SPECIAL",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Card Title
                    const Text(
                      'Harvest Energy Bowl',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    // Card Subtitle
                    const Text(
                      'Get 20% off during lunch hours!',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(height: 12),

                    // "Order Now" Button
                    ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                      ),
                      child: const Text(
                        'Order Now',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CardRowItems extends StatelessWidget {
  final String title;
  final List<FoodItem> items;
  final int maxItems;

  const CardRowItems({
    super.key,
    required this.title,
    required this.items,
    this.maxItems = 5, // Default limit set to 5 items max
  });

  @override
  Widget build(BuildContext context) {
    final displayedItems = items.take(maxItems).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Menu Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: () {},
              icon: Icon(Icons.arrow_forward),
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                iconSize:
                    19, // Shrinks the background wrapper tight around the icon
              ),
            ),
          ],
        ),

        // Horizontal Scrollable Cards List
        SizedBox(
          height: 250, // Fixed height for the card container
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: displayedItems.length,
            itemBuilder: (context, index) {
              final item = displayedItems[index];
              return Container(
                width: 220, // Fixed width for each card
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Card(
                  elevation: 0,
                  color: Colors.transparent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Food Image
                      Stack(
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

                          Positioned(
                            right: 5,
                            bottom: 5,
                            child: Container(
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
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),

                      // Card Details
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11),
                            ),
                            Row(
                              children: [
                                Text(
                                  item.rating.toString(),
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
                            Text(
                              'Tsh${item.price}',
                              style: const TextStyle(
                                color: Colors.black, // Dark green tone
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class QuickBites extends StatelessWidget {
  const QuickBites({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(vertical: 2),

          children: [
            Card(
              elevation: 0,
              color: Colors.blue,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  height: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Icon(Icons.coffee_outlined),
                      const SizedBox(height: 24),
                      Text(
                        "Coffee & Tea",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Card(
              elevation: 0,
              color: Colors.green,

              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  height: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Icon(Icons.icecream),
                      const SizedBox(height: 24),
                      Text(
                        "Deserts",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(
              0xFFFFE5CC,
            ), // Peach / Light Orange shade matching the design
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.wine_bar_sharp),
                  Text(
                    'Fresh smothies',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              Icon(Icons.arrow_forward, color: Colors.deepOrange),
            ],
          ),
        ),
      ],
    );
  }
}
