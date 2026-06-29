import '../data/food_data.dart';

class CartItem {
  final FoodItem foodItem;
  int quantity;

  CartItem({
    required this.foodItem,
    this.quantity = 1,
  });
}
