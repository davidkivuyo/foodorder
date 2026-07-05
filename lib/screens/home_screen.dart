import 'package:flutter/material.dart';
import '../data/food_data.dart';
import '../data/search_bar.dart';
import '../services/cart_service.dart';
import '../widgets/cart_fab.dart';
import 'common_food.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<FoodItem>>(
          stream: FoodData.foodItemsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(
                    'Error loading meals: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final allItems = snapshot.data ?? [];

            final campusFavourites = allItems
                .where((f) => f.section == 'campus_favourite')
                .toList();
            final todaysDeals = allItems
                .where((f) => f.section == 'todays_deals')
                .toList();
            final drinks = allItems
                .where((f) => f.section == 'drinks')
                .toList();
            final offCampus = allItems
                .where((f) => f.section == 'off_campus')
                .toList();
            final other = allItems.where((f) => f.section == 'other').toList();

            return SingleChildScrollView(
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

                    // card grid
                    CardRowItems(
                      title: "Favourite on campus",
                      items: campusFavourites,
                    ),
                    const Divider(),
                    CardRowItems(title: "Today's Deals", items: todaysDeals),
                    const Divider(),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Common loved foods',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    CommonFood(),

                    const Divider(),
                    CardRowItems(title: "Drinks Deals!", items: drinks),
                    const Divider(),
                    CardRowItems(
                      title: "Deals outside campus",
                      items: offCampus,
                    ),
                    const Divider(),
                    CardColumnItems(
                      title: "Other meal deals",
                      items: other,
                      flipItems: true,
                    ),
                  ],
                ),
              ),
            );
          },
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
              image: NetworkImage(
                'https://images.unsplash.com/photo-1544025162-d76694265947?w=600',
              ),
              fit: BoxFit.cover,
            ),
          ),
          child: Stack(
            children: [
              // Explicitly Positioned Fill layout to guarantee visibility of content
              Positioned(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Order Food Easily',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),

                        Text(
                          'Without The Waiting!',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
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
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CategoriesTitles(
                        title: title,
                        items: flipItems ? items.reversed.toList() : items,
                      ),
                    ),
                  );
                },
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
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ItemDescriptionsHome(item: item),
                                    ),
                                  );
                                },
                                child: Hero(
                                  tag:
                                      'home_${item.cafe}_${item.title}_${item.image}',
                                  child: item.buildImage(
                                    height: 120,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
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

                              // Inside CardRowItems where you display the rating & cafe text:
                              Row(
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber,
                                    size: 16,
                                  ),
                                  Expanded(
                                    child: Text(
                                      // If cafe is 'offcampus', show 'OFF-CAMPUS', otherwise show 'CAFE(X)'
                                      item.cafe.toLowerCase() == 'offcampus'
                                          ? '${item.rating} • offcampus'
                                          : '${item.rating} • CAFE(${item.cafe})',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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

class ItemDescriptionsHome extends StatelessWidget {
  final FoodItem item;

  const ItemDescriptionsHome({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // no-op: prevents any duplicate pop from propagating to system back / app exit
      },
      child: Scaffold(
        floatingActionButton: const CartFab(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Hero(
                    tag: 'home_${item.cafe}_${item.title}_${item.image}',
                    child: ClipRRect(
                      child: item.buildImage(
                        width: double.infinity,
                        height: 220,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),

                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CircleAvatar(
                        backgroundColor: Colors.black45,
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.maybePop(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      item.subtitle,
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),

                    const SizedBox(height: 20),

                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber),
                        const SizedBox(width: 5),
                        Text("${item.rating}"),
                        const Spacer(),
                        Text(
                          "TZS ${item.price}",
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Colors.orange, // Button background color
                          foregroundColor: Colors.white, // Text and icon color
                          elevation: 1, // Shadow depth
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              10,
                            ), // Rounded corners
                          ),
                        ),
                        onPressed: () {
                          CartService().addToCart(item);
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${item.title} added to cart!'),
                              duration: const Duration(seconds: 1),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.shopping_cart),
                            SizedBox(width: 8),
                            Text('I want this!🤩'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CategoriesTitles extends StatelessWidget {
  final String title;
  final List<FoodItem> items;

  const CategoriesTitles({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      floatingActionButton: const CartFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: ListView.builder(
        padding: const EdgeInsets.all(10.0),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 2.2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ItemDescriptionsHome(item: item),
                          ),
                        );
                      },
                      child: Hero(
                        tag: 'home_${item.cafe}_${item.title}_${item.image}',
                        child: item.buildImage(
                          height: 100,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              CartService().addToCart(item);
                              ScaffoldMessenger.of(
                                context,
                              ).hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${item.title} added to cart!'),
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
                                semanticLabel: 'add item',
                              ),
                            ),
                          ),
                        ],
                      ),

                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.amber,
                            size: 16,
                          ),
                          Expanded(
                            child: Text(
                              // If cafe is 'offcampus', show 'OFF-CAMPUS', otherwise show 'CAFE(X)'
                              item.cafe.toLowerCase() == 'offcampus'
                                  ? '${item.rating} • offcampus'
                                  : '${item.rating} • CAFE(${item.cafe})',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class CardColumnItems extends StatelessWidget {
  final String title;
  final List<FoodItem> items;
  final bool flipItems;

  const CardColumnItems({
    super.key,
    required this.title,
    required this.items,
    this.flipItems = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayedItems = flipItems ? items.reversed.toList() : items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),

        // Vertical list — shrinkWrap + NeverScrollableScrollPhysics
        // so it plays nicely inside the parent SingleChildScrollView
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          itemCount: displayedItems.length,
          itemBuilder: (context, index) {
            final item = displayedItems[index];

            return Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Food image — same AspectRatio as category_screen FoodCard
                  AspectRatio(
                    aspectRatio: 2.2,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ItemDescriptionsHome(item: item),
                            ),
                          );
                        },
                        child: Hero(
                          tag: 'home_${item.cafe}_${item.title}_${item.image}',
                          child: item.buildImage(
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Item details
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                            const SizedBox(width: 8),
                            // Add to cart button
                            GestureDetector(
                              onTap: () {
                                CartService().addToCart(item);
                                ScaffoldMessenger.of(
                                  context,
                                ).hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
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
                                decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.add_rounded,
                                  color: Colors.white,
                                  size: 18,
                                  semanticLabel: 'add item',
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Subtitle
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),

                        // Rating and cafe row
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 16,
                            ),
                            Expanded(
                              child: Text(
                                item.cafe.toLowerCase() == 'offcampus'
                                    ? '${item.rating} • offcampus'
                                    : '${item.rating} • CAFE(${item.cafe})',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
