import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/food_data.dart';
import '../services/cart_service.dart';
import '../widgets/cart_fab.dart';
import 'home_screen.dart';

// ---------------------------------------------------------------------------
// Data model for a common-food category shown in the horizontal scroll list.
// Images are placeholder Firebase Storage URLs – ready to be replaced with
// real URLs fetched from Firestore once that phase is activated.
// ---------------------------------------------------------------------------
class _CommonFoodItem {
  final String title;
  final String prepTime;
  final String imageUrl; // Firebase Storage URL (placeholder for now)

  const _CommonFoodItem({
    required this.title,
    required this.prepTime,
    required this.imageUrl,
  });
}

// Static mock data – images are grey placeholders that will later be replaced
// by real Firebase Storage URLs fetched from Firestore.
const List<_CommonFoodItem> _commonFoods = [
  _CommonFoodItem(
    title: 'Wali',
    prepTime: '15 min',
    imageUrl:
        'https://firebasestorage.googleapis.com/v0/b/foodorder-8ffcf.firebasestorage.app/o/ricemeat.jpg?alt=media&token=991583e9-c419-4353-ac0d-d0dac890adf9', // will be fetched from Firebase Storage
  ),
  _CommonFoodItem(
    title: 'Ugali',
    prepTime: '20 min',
    imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/4/48/Ugali_%26_Sukuma_Wiki.jpg', // will be fetched from Firebase Storage
  ),
  _CommonFoodItem(
    title: 'Chipsi',
    prepTime: '10 min',
    imageUrl:
        'https://firebasestorage.googleapis.com/v0/b/foodorder-8ffcf.firebasestorage.app/o/chips.jpg?alt=media&token=40aefb61-1714-4de3-87a1-f882e5a4b007', // will be fetched from Firebase Storage
  ),
  _CommonFoodItem(
    title: 'Pilau',
    prepTime: '25 min',
    imageUrl:
        'https://firebasestorage.googleapis.com/v0/b/foodorder-8ffcf.firebasestorage.app/o/biriyanimeat.jpg?alt=media&token=b69a46d5-d94e-455f-848d-d7dec9ed06fb', // will be fetched from Firebase Storage
  ),
];

// ---------------------------------------------------------------------------
// CommonFood – horizontal scrollable list of circular food category items.
// Shown on the home screen via CommonFood().
// ---------------------------------------------------------------------------
class CommonFood extends StatelessWidget {
  const CommonFood({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _commonFoods.length,
        separatorBuilder: (_, _) => const SizedBox(width: 20),
        itemBuilder: (context, index) {
          final food = _commonFoods[index];
          return _CommonFoodCircle(food: food);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A single circular item in the horizontal list.
// ---------------------------------------------------------------------------
class _CommonFoodCircle extends StatelessWidget {
  final _CommonFoodItem food;

  const _CommonFoodCircle({required this.food});

  Widget _buildCircleImage() {
    final bool hasUrl =
        food.imageUrl.startsWith('http://') ||
        food.imageUrl.startsWith('https://');

    if (hasUrl) {
      return CachedNetworkImage(
        imageUrl: food.imageUrl,
        imageBuilder: (context, imageProvider) => Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
          ),
        ),
        placeholder: (context, url) => _placeholder(),
        errorWidget: (context, url, error) => _placeholder(),
      );
    }

    // No URL yet – show a styled placeholder ready for Firebase Storage
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(shape: BoxShape.circle),
      child: const Icon(Icons.restaurant, size: 32, color: Colors.black),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CommonFoodList(food: food)),
        );
      },
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Circular image with a subtle orange ring
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(shape: BoxShape.circle),
              child: ClipOval(child: _buildCircleImage()),
            ),

            const SizedBox(height: 6),

            // Food title
            Text(
              food.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),

            const SizedBox(height: 2),

            // Prep time
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  food.prepTime,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CommonFoodList – vertical list of food items corresponding to the tapped
// common-food category.  Layout mirrors the category screen (FoodCard style).
// No AppBar – uses a custom back button instead.
// ---------------------------------------------------------------------------
class CommonFoodList extends StatelessWidget {
  // ignore: library_private_types_in_public_api
  final _CommonFoodItem food;

  // ignore: library_private_types_in_public_api
  const CommonFoodList({super.key, required this.food});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: const CartFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
                    'Error loading items: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            // Filter items whose title contains the common food name (case-insensitive).
            // When Firestore has a dedicated field/tag for common-food categories this
            // filter can be updated accordingly.
            final allItems = snapshot.data ?? [];
            final filtered = allItems.where((item) {
              return item.title.toLowerCase().contains(
                food.title.toLowerCase(),
              );
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Custom header (no AppBar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
                  child: Row(
                    children: [
                      // Back button
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Title matches the tapped category
                      Text(
                        food.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Vertical food list ─────────────────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.restaurant_menu,
                                  size: 64,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No ${food.title} items available yet.',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(10.0),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 24.0),
                              child: _CommonFoodCard(item: item),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CommonFoodCard – single food card in the vertical list.
// Layout identical to the category screen's FoodCard.
// ---------------------------------------------------------------------------
class _CommonFoodCard extends StatelessWidget {
  final FoodItem item;

  const _CommonFoodCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Food image (tappable → detail screen) ───────────────────────
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
                tag: 'common_${item.cafe}_${item.title}_${item.image}',
                child: item.buildImage(
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),

        // ── Card details ────────────────────────────────────────────────
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
                  // Add to cart button
                  GestureDetector(
                    onTap: () {
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
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF5820D),
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

              // Prep time row
              Row(
                children: [
                  Text(
                    item.time,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),

              const SizedBox(height: 2),

              // Rating & cafe row
              Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                  Expanded(
                    child: Text(
                      item.cafe.toLowerCase() == 'offcampus'
                          ? '${item.rating} • offcampus'
                          : '${item.rating} • CAFE(${item.cafe})',
                      style: const TextStyle(fontSize: 12, color: Colors.black),
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
    );
  }
}
