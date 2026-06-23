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
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "What's your bite today?",
                  style: TextStyle(
                    color: Color.fromARGB(255, 138, 83, 0),
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                //space between text and searchbar
                const SizedBox(height: 8),

                // search bar
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 214, 214, 214),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const TextField(
                    decoration: InputDecoration(
                      hintText: 'Search foods, snacks and drinks',
                      border: InputBorder.none,
                      icon: Icon(Icons.search),
                    ),
                  ),
                ),

                //space
                const SizedBox(height: 24),

                // banner
                SpecialBannerCard(),

                // space
                const SizedBox(height: 24),

                // card grid for cafe 1
                CardGridCafe1(),

                // space
                const SizedBox(height: 24),

                // card grid for cafe 2
                CardGridCafe2(),
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

class CardGridCafe1 extends StatelessWidget {
  const CardGridCafe1({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> menuItems = [
      {
        'image': 'designs/assets/grilled-meat.jpg',
        'title': 'Smoked grilled meat',
        'subtitle': 'Fresh Steak out of the gill',
        'price': 'tsh 15000',
      },
      {
        'image': 'designs/assets/chips.jpg',
        'title': 'Chips Mshkaki',
        'subtitle': 'Served with your favourite additive',
        'price': 'tsh 3000',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Menu Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Today's Menu: CAFE 1",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E1E1E),
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: Icon(Icons.arrow_forward),
              style: IconButton.styleFrom(
                backgroundColor: Colors.grey[200],
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
            itemCount: menuItems.length,
            itemBuilder: (context, index) {
              final item = menuItems[index];
              return Container(
                width: 220, // Fixed width for each card
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Food Image
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            image: DecorationImage(
                              image: AssetImage(item['image']!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),

                      // Card Details
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title']!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item['subtitle']!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Price and Add Button Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  item['price']!,
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
              );
            },
          ),
        ),
      ],
    );
  }
}

class CardGridCafe2 extends StatelessWidget {
  // Constructor
  const CardGridCafe2({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> menuItems = [
      {
        'image': 'designs/assets/sandwich.jpg',
        'title': 'Honey Sandwich',
        'subtitle': 'Fresh sandwich for your breakfast',
        'price': 'tsh 1000',
      },
      {
        'image': 'designs/assets/burgerchips.jpg',
        'title': 'Burger with fries',
        'subtitle': 'Served with your favourite additive',
        'price': 'tsh 7000',
      },
      {
        'image': 'designs/assets/biriyanimeat.jpg',
        'title': 'Biriyani With meat',
        'subtitle': 'full one plate satisfaction',
        'price': 'tsh 2500',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Menu Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Today's Menu: CAFE 2",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E1E1E),
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: Icon(Icons.arrow_forward),
              style: IconButton.styleFrom(
                backgroundColor: Colors.grey[200],
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
            itemCount: menuItems.length,
            itemBuilder: (context, index) {
              final item = menuItems[index];
              return Container(
                width: 220, // Fixed width for each card
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Food Image
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            image: DecorationImage(
                              image: AssetImage(item['image']!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),

                      // Card Details
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title']!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item['subtitle']!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Price and Add Button Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  item['price']!,
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
                                    color: Colors.black,
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
    return Placeholder();
  }
}
