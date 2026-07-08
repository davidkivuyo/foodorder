import '../data/food_data.dart';

class CartItem {
  final String id;
  final FoodItem foodItem;
  int quantity;

  CartItem({
    required this.id,
    required this.foodItem,
    this.quantity = 1,
  });
}
