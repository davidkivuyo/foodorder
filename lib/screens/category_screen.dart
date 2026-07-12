import 'package:flutter/material.dart';
import '../data/food_data.dart';
import '../widgets/cafe_selection_dialog.dart';
import '../widgets/cart_fab.dart';

class _Category {
  final String display;
  final String value;
  const _Category(this.display, this.value);
}

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  String _selectedCategory = 'All';

  static const List<_Category> _categories = [
    _Category('🍽️ All', 'All'),
    _Category('🥞 Breakfast', 'Breakfast'),
    _Category('🍴 Lunch', 'Lunch'),
    _Category('🥮 Dinner', 'Dinner'),
    _Category('🍕 Teasers', 'Teasers'),
    _Category('🥂 Drinks', 'Drinks'),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FoodItem>>(
      stream: FoodData.foodItemsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                'Error loading categories: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        final allItems = snapshot.data ?? [];
        final filteredItems = _selectedCategory == 'All'
            ? allItems
            : allItems
                  .where(
                    (item) =>
                        item.category.toLowerCase() ==
                        _selectedCategory.toLowerCase(),
                  )
                  .toList();

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Explore Categories',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: .75,
                  ),
                ),
                const Text(
                  'Find the best meal for your study break!',
                  style: TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 18),
                _buildCategoryChips(),
                const SizedBox(height: 18),
                filteredItems.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No items found for $_selectedCategory',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      )
                    : Cards(items: filteredItems),
                //const SizedBox(height: 10),
                //BottomBanner(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 45,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = category.value == _selectedCategory;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategory = category.value;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
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
                    category.display,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color.fromARGB(255, 61, 61, 61),
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class Cards extends StatelessWidget {
  final List<FoodItem> items;
  const Cards({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: FoodCard(item: items[index]),
        );
      },
    );
  }
}

class FoodCard extends StatelessWidget {
  final FoodItem item;

  const FoodCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
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
                    builder: (_) => ItemDescriptionsCategories(item: item),
                  ),
                );
              },
              child: Hero(
                tag: 'category_${item.displayCafe}_${item.title}_${item.image}',
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
          padding: EdgeInsets.all(4),
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
                      addToCartWithCafeCheck(context, item);
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
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                  Text(
                    '${item.rating} • ',
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Icon(
                    Icons.storefront_outlined,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                  Text(
                    item.displayCafe,
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/*class BottomBanner extends StatelessWidget {
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
}*/

class ItemDescriptionsCategories extends StatelessWidget {
  final FoodItem item;

  const ItemDescriptionsCategories({super.key, required this.item});

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
                    tag:
                        'category_${item.displayCafe}_${item.title}_${item.image}',
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
                          addToCartWithCafeCheck(context, item);
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.shopping_cart),
                            SizedBox(width: 8),
                            Text('add to cart'),
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
