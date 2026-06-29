import 'package:flutter/material.dart';
import '../data/food_data.dart';
import '../data/search_bar.dart';
import '../services/cart_service.dart';

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
        cafe: '1',
        time: '10min',
      ),
      FoodItem(
        image: 'designs/assets/grilled-meat.jpg',
        title: 'Smoked grilled meat',
        subtitle: 'Fresh Steak out of the gill',
        price: 18000,
        rating: 4.8,
        category: '',
        cafe: '1',
        time: '5min',
      ),
      FoodItem(
        image: 'designs/assets/chips.jpg',
        title: 'Chips Mshkaki',
        subtitle: 'Served with additives',
        price: 3000,
        rating: 4.3,
        category: '',
        cafe: '1',
        time: '7min',
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
        cafe: '2',
        time: '12min',
      ),
      FoodItem(
        image: 'designs/assets/burgerchips.jpg',
        title: 'Burger with fries',
        subtitle: 'Served warm and fast',
        price: 7000,
        rating: 3.9,
        category: '',
        cafe: '1',
        time: '10min',
      ),
      FoodItem(
        image: 'designs/assets/biriyanimeat.jpg',
        title: 'Biriyani With meat',
        subtitle: 'Full plate satisfaction',
        price: 2500,
        rating: 4.7,
        category: '',
        cafe: '2',
        time: '5min',
      ),
    ];

    final List<FoodItem> drinkDeals = [
      FoodItem(
        image: 'designs/assets/juiceavocado.jpg',
        title: 'Avocado juice',
        subtitle: 'Full orange flavour',
        price: 1000,
        rating: 4.5,
        category: '',
        cafe: 'ALL',
        time: '12min',
      ),
      FoodItem(
        image: 'designs/assets/juicex2.jpg',
        title: 'Mango juice',
        subtitle: 'True mango',
        price: 7000,
        rating: 4.8,
        category: '',
        cafe: '2',
        time: '10min',
      ),
      FoodItem(
        image: 'designs/assets/juice.jpg',
        title: 'orange juice',
        subtitle: 'Fresh from field',
        price: 2500,
        rating: 4.7,
        category: '',
        cafe: '2',
        time: '5min',
      ),
    ];

    return Scaffold(
      // home screen body
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // search bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SearchBarScreen(),
                        ),
                      );
                    },
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 18),

                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search,
                            color: Colors.black87,
                            size: 24,
                          ),
                          const SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              "Search your next meal",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                //space
                const SizedBox(height: 18),

                // banner
                SpecialBannerCard(),

                // space
                const SizedBox(height: 18),

                // card grid
                CardRowItems(
                  title: "Favourite on campus",
                  items: cafe1Menu,
                  maxItems: 4,
                ),
                const Divider(),

                // card grid
                CardRowItems(
                  title: "Today's Deals",
                  items: cafe2Menu,
                  maxItems: 4,
                ),
                const Divider(),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    "Quick Bites",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                QuickBites(),

                const Divider(),

                // card grid
                CardRowItems(
                  title: "Featured on Campus Bite",
                  items: cafe1Menu,
                  maxItems: 4,
                  flipItems: true,
                ),

                const Divider(),

                CardRowItems(
                  title: "Drinks Deals!",
                  items: drinkDeals,
                  maxItems: 4,
                ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Center(
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
                      Colors.black.withValues(
                        alpha: 0.75,
                      ), // Darker on the left
                      Colors.black.withValues(
                        alpha: 0.1,
                      ), // Clearer on the right
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
      ),
    );
  }
}

class CardRowItems extends StatelessWidget {
  final String title;
  final List<FoodItem> items;
  final int maxItems;
  final bool flipItems;

  const CardRowItems({
    super.key,
    required this.title,
    required this.items,
    this.maxItems = 5,
    this.flipItems = false, // Default limit set to 5 items max
  });

  @override
  Widget build(BuildContext context) {
    final displayedItems = flipItems
        ? items.reversed.take(maxItems).toList()
        : items.take(maxItems).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Menu Header Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () {},
                icon: Icon(Icons.arrow_forward, semanticLabel: 'more items'),
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  iconSize: 19,
                ),
              ),
            ],
          ),
        ),

        // Horizontal Scrollable Cards List
        SizedBox(
          height: 200, // Fixed height for the card container
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
                              child: Hero(
                                tag: item.image,
                                child: Image.asset(
                                  item.image,
                                  height: 120,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Card Details
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      CartService().addToCart(item);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).hideCurrentSnackBar();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${item.title} added to cart!',
                                          ),
                                          duration: const Duration(seconds: 1),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.orange,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.add_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${item.subtitle} • ${item.time}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11),
                              ),

                              Row(
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber,
                                    size: 16,
                                  ),
                                  Text(
                                    '${item.rating.toString()} • CAFE(${item.cafe})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            childAspectRatio: 1.3,
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
                Icon(Icons.arrow_forward, color: Colors.orange),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
