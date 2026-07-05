import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';
import '../models/order.dart';
import '../data/food_data.dart';

class CartService extends ChangeNotifier {
  // Singleton pattern to share state across screens
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal() {
    _loadCart();
  }

  static const String _cartKey = 'cart_items_v1';

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

  // ---------- Persistence ----------

  /// Load persisted cart from shared_preferences on startup.
  Future<void> _loadCart() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cartKey);
    if (raw == null) return;

    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      for (final entry in decoded) {
        final map = entry as Map<String, dynamic>;
        final quantity = (map['quantity'] as num).toInt();

        final foodItem = FoodItem(
          image: map['image'] as String,
          title: map['title'] as String,
          subtitle: map['subtitle'] as String,
          price: (map['price'] as num).toInt(),
          rating: (map['rating'] as num).toDouble(),
          category: map['category'] as String,
          cafe: map['cafe'] as String,
          time: map['time'] as String,
          section: (map['section'] as String?) ?? '',
        );
        _cartItems.add(CartItem(foodItem: foodItem, quantity: quantity));
      }
      notifyListeners();
    } catch (_) {
      // If data is stale or corrupt, start with a fresh cart.
      _cartItems.clear();
    }
  }

  /// Persist the current cart to shared_preferences.
  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _cartItems
          .map((item) => {
                'title': item.foodItem.title,
                'subtitle': item.foodItem.subtitle,
                'image': item.foodItem.image,
                'price': item.foodItem.price,
                'rating': item.foodItem.rating,
                'category': item.foodItem.category,
                'cafe': item.foodItem.cafe,
                'time': item.foodItem.time,
                'section': item.foodItem.section,
                'quantity': item.quantity,
              })
          .toList(),
    );
    await prefs.setString(_cartKey, encoded);
  }

  // ---------- Cart Operations ----------

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
    _saveCart();
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
      _saveCart();
    }
  }

  void deleteFromCart(FoodItem item) {
    _cartItems.removeWhere(
      (element) => element.foodItem.title == item.title && element.foodItem.cafe == item.cafe,
    );
    notifyListeners();
    _saveCart();
  }

  void clearCart() {
    _cartItems.clear();
    notifyListeners();
    _saveCart();
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
