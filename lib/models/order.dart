import 'cart_item.dart';

enum OrderStatus { preparing, ready, collected }

class FoodOrder {
  final String orderId;
  final List<CartItem> items;
  final double totalAmount;
  final DateTime orderTime;
  OrderStatus status;

  FoodOrder({
    required this.orderId,
    required this.items,
    required this.totalAmount,
    required this.orderTime,
    this.status = OrderStatus.preparing,
  });
}
