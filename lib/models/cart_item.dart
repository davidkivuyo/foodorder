import '../data/food_data.dart';

class CartItem {
  final String id;
  final FoodItem foodItem;
  int quantity;
  final String? selectedCafe;

  CartItem({
    required this.id,
    required this.foodItem,
    this.quantity = 1,
    this.selectedCafe,
  });

  String get displayCafe => selectedCafe ?? foodItem.displayCafe;
}
