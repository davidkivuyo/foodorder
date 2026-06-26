class FoodItem {
  final String image;
  final String title;
  final String subtitle;
  final double price;
  final double rating;
  final String category;

  const FoodItem({
    required this.image,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.rating,
    required this.category,
  });

  factory FoodItem.fromMap(Map<String, dynamic> map) {
    return FoodItem(
      image: map['image'] ?? '',
      title: map['title'] ?? '',
      subtitle: map['subtitle'] ?? '',
      price: map['price'] ?? '',
      rating: (map['rating'] ?? 4.5).toDouble(),
      category: '',
    );
  }
}
