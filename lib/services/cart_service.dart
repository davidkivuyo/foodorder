import 'dart:async';
import 'package:flutter/material.dart';
import '../models/cart_item.dart';
import '../models/order.dart';
import '../data/food_data.dart';

class CartService extends ChangeNotifier {
  // Singleton pattern to share state across screens
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  final List<CartItem> _cartItems = [];
  final List<FoodOrder> _orders = [];

  List<CartItem> get cartItems => List.unmodifiable(_cartItems);
  List<FoodOrder> get orders => List.unmodifiable(_orders);

  double get totalAmount {
    return _cartItems.fold(0.0, (sum, item) => sum + (item.foodItem.price * item.quantity));
  }

  int get totalItemsCount {
    return _cartItems.fold(0, (sum, item) => sum + item.quantity);
  }

  void addToCart(FoodItem item) {
    final index = _cartItems.indexWhere(
      (element) => element.foodItem.title == item.title && element.foodItem.cafe == item.cafe,
    );
    if (index >= 0) {
      _cartItems[index].quantity++;
    } else {
      _cartItems.add(CartItem(foodItem: item));
    }
    notifyListeners();
  }

  void removeFromCart(FoodItem item) {
    final index = _cartItems.indexWhere(
      (element) => element.foodItem.title == item.title && element.foodItem.cafe == item.cafe,
    );
    if (index >= 0) {
      if (_cartItems[index].quantity > 1) {
        _cartItems[index].quantity--;
      } else {
        _cartItems.removeAt(index);
      }
      notifyListeners();
    }
  }

  void deleteFromCart(FoodItem item) {
    _cartItems.removeWhere(
      (element) => element.foodItem.title == item.title && element.foodItem.cafe == item.cafe,
    );
    notifyListeners();
  }

  void clearCart() {
    _cartItems.clear();
    notifyListeners();
  }

  void placeOrder() {
    if (_cartItems.isEmpty) return;

    final newOrderId = 'CB-${1000 + _orders.length + (DateTime.now().millisecond % 9000)}';
    final newOrder = FoodOrder(
      orderId: newOrderId,
      items: List.from(_cartItems),
      totalAmount: totalAmount,
      orderTime: DateTime.now(),
      status: OrderStatus.preparing,
    );

    _orders.insert(0, newOrder);
    clearCart();
    notifyListeners();

    // Simulating Cafe Admin response:
    // After 8 seconds, the order status changes to Ready (simulating admin marking it ready).
    Timer(const Duration(seconds: 8), () {
      final index = _orders.indexWhere((o) => o.orderId == newOrderId);
      if (index >= 0) {
        _orders[index].status = OrderStatus.ready;
        notifyListeners();
      }
    });

    // After 18 seconds, the order status changes to Collected (simulating confirmation).
    Timer(const Duration(seconds: 18), () {
      final index = _orders.indexWhere((o) => o.orderId == newOrderId);
      if (index >= 0) {
        _orders[index].status = OrderStatus.collected;
        notifyListeners();
      }
    });
  }

  // Helper method to simulate immediate admin status changes from the UI
  void simulateAdminStatusChange(String orderId, OrderStatus newStatus) {
    final index = _orders.indexWhere((o) => o.orderId == orderId);
    if (index >= 0) {
      _orders[index].status = newStatus;
      notifyListeners();
    }
  }
}
