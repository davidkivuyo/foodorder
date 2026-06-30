class FoodItem {
  final String image;
  final String title;
  final String subtitle;
  final double price;
  final double rating;
  final String category;
  final String cafe;
  final String time;
  final String section;

  const FoodItem({
    required this.image,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.rating,
    required this.category,
    required this.cafe,
    required this.time,
    this.section = '',
  });

  factory FoodItem.fromMap(Map<String, dynamic> map) {
    return FoodItem(
      image: map['image'] ?? '',
      title: map['title'] ?? '',
      subtitle: map['subtitle'] ?? '',
      price: map['price'] ?? '',
      rating: (map['rating'] ?? 4.5).toDouble(),
      category: '',
      cafe: map['cafe'] ?? 'all',
      time: map['time'] ?? '',
    );
  }
}

// food_data.dart

class FoodData {
  static const List<FoodItem> all = [
    // --- Cafe 1 ---
    FoodItem(
      image: 'designs/assets/ricemeat.jpg',
      title: 'Wali Nyama',
      subtitle: 'Fresh for your appetite',
      price: 2500,
      rating: 4.5,
      category: 'Lunch',
      cafe: '1',
      time: '10min',
      section: 'campus_favourite',
    ),
    FoodItem(
      image: 'designs/assets/grilled-meat.jpg',
      title: 'Smoked grilled meat',
      subtitle: 'Fresh Steak out of the grill',
      price: 18000,
      rating: 4.8,
      category: 'Dinner',
      cafe: '1',
      time: '5min',
      section: 'campus_favourite',
    ),
    FoodItem(
      image: 'designs/assets/chips.jpg',
      title: 'Chips Mshkaki',
      subtitle: 'Served with additives',
      price: 3000,
      rating: 4.3,
      category: 'Dinner',
      cafe: '1',
      time: '7min',
      section: 'campus_favourite',
    ),

    // --- Cafe 2 / Today's Deals ---
    FoodItem(
      image: 'designs/assets/sandwich.jpg',
      title: 'Honey Sandwich',
      subtitle: 'Fresh breakfast choice',
      price: 1000,
      rating: 4,
      category: 'Breakfast',
      cafe: '2',
      time: '12min',
      section: 'todays_deals',
    ),
    FoodItem(
      image: 'designs/assets/burgerchips.jpg',
      title: 'Burger with fries',
      subtitle: 'Served warm and fast',
      price: 7000,
      rating: 3.9,
      category: 'Lunch',
      cafe: '1',
      time: '10min',
      section: 'todays_deals',
    ),
    FoodItem(
      image: 'designs/assets/biriyanimeat.jpg',
      title: 'Biriyani With meat',
      subtitle: 'Full plate satisfaction',
      price: 2500,
      rating: 4.7,
      category: 'Lunch',
      cafe: '2',
      time: '5min',
      section: 'todays_deals',
    ),

    // --- Drinks ---
    FoodItem(
      image: 'designs/assets/juiceavocado.jpg',
      title: 'Avocado juice',
      subtitle: 'Full orange flavour',
      price: 1000,
      rating: 4.5,
      category: 'Drinks',
      cafe: 'ALL',
      time: '2min',
      section: 'drinks',
    ),
    FoodItem(
      image: 'designs/assets/juicex2.jpg',
      title: 'Mango juice',
      subtitle: 'True mango',
      price: 7000,
      rating: 4.8,
      category: 'Drinks',
      cafe: '2',
      time: '2min',
      section: 'drinks',
    ),
    FoodItem(
      image: 'designs/assets/juice.jpg',
      title: 'Orange juice',
      subtitle: 'Fresh from field',
      price: 2500,
      rating: 4.7,
      category: 'Drinks',
      cafe: '2',
      time: '5min',
      section: 'drinks',
    ),

    // --- Off Campus ---
    FoodItem(
      image: 'designs/assets/pizzaplate.jpg',
      title: 'Pizza pepperoni',
      subtitle: 'The pizza you want',
      price: 20000,
      rating: 4.8,
      category: 'Dinner',
      cafe: 'offcampus',
      time: '12min',
      section: 'off_campus',
    ),
    FoodItem(
      image: 'designs/assets/friedchicken.jpg',
      title: 'Chicken wings',
      subtitle: 'As tasty as it looks',
      price: 19000,
      rating: 4.9,
      category: 'Dinner',
      cafe: 'offcampus',
      time: '10min',
      section: 'off_campus',
    ),
    FoodItem(
      image: 'designs/assets/heavyburger.jpg',
      title: 'Heavy burger',
      subtitle: 'Your favourite burger is here',
      price: 15000,
      rating: 4.7,
      category: 'Dinner',
      cafe: 'offcampus',
      time: '20min',
      section: 'off_campus',
    ),
  ];

  // Named filtered views — used directly by HomeScreen
  static List<FoodItem> get campusFavourites =>
      all.where((f) => f.section == 'campus_favourite').toList();

  static List<FoodItem> get todaysDeals =>
      all.where((f) => f.section == 'todays_deals').toList();

  static List<FoodItem> get drinks =>
      all.where((f) => f.section == 'drinks').toList();

  static List<FoodItem> get offCampus =>
      all.where((f) => f.section == 'off_campus').toList();
}
