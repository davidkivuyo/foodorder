import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/cart_item.dart';
import '../models/order.dart';
import '../data/food_data.dart';

class CartService extends ChangeNotifier {
  // Singleton pattern to share state across screens
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal() {
    _initAuthListener();
  }

  final List<CartItem> _cartItems = [];
  final List<FoodOrder> _orders = [];
  final Map<String, FoodItem> _foodItemsCache = {};

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot>? _cartSubscription;

  List<CartItem> get cartItems => List.unmodifiable(_cartItems);
  List<FoodOrder> get orders => List.unmodifiable(_orders);

  double get totalAmount {
    return _cartItems.fold(
      0.0,
      (total, item) => total + (item.foodItem.price * item.quantity),
    );
  }

  int get totalItemsCount {
    return _cartItems.fold(0, (total, item) => total + item.quantity);
  }

  // ---------- Firestore Sync ----------

  void _initAuthListener() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _listenToCart(user.uid);
      } else {
        _cancelCartSubscription();
        _cartItems.clear();
        notifyListeners();
      }
    });
  }

  void _listenToCart(String userId) {
    _cancelCartSubscription();
    _cartSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('cart')
        .snapshots()
        .listen((snapshot) async {
          final List<CartItem> updatedItems = [];

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final foodItemId = data['foodItemId'] as String?;
            final quantity = (data['quantity'] as num?)?.toInt() ?? 1;
            final selectedCafe = data['selectedCafe'] as String?;

            if (foodItemId == null || foodItemId.isEmpty) continue;

            // Fetch FoodItem details from cache or Firestore
            FoodItem? foodItem = _foodItemsCache[foodItemId];
            if (foodItem == null) {
              try {
                final foodDoc = await FirebaseFirestore.instance
                    .collection('food_items')
                    .doc(foodItemId)
                    .get();
                if (foodDoc.exists && foodDoc.data() != null) {
                  foodItem = FoodItem.fromMap(foodDoc.data()!, id: foodDoc.id);
                  _foodItemsCache[foodItemId] = foodItem;
                }
              } catch (e) {
                debugPrint(
                  '[CartService] Error fetching food item $foodItemId: $e',
                );
              }
            }

            if (foodItem != null) {
              updatedItems.add(
                CartItem(
                  id: doc.id,
                  foodItem: foodItem,
                  quantity: quantity,
                  selectedCafe: selectedCafe,
                ),
              );
            }
          }

          _cartItems.clear();
          _cartItems.addAll(updatedItems);
          notifyListeners();
        });
  }

  void _cancelCartSubscription() {
    _cartSubscription?.cancel();
    _cartSubscription = null;
  }

  // ---------- Cart Operations ----------

  void addToCart(FoodItem item, {String? selectedCafe}) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || item.id.isEmpty) return;

    final cartCollection = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('cart');

    final existingIndex = _cartItems.indexWhere(
      (element) => element.foodItem.id == item.id,
    );

    try {
      if (existingIndex >= 0) {
        final existingItem = _cartItems[existingIndex];
        await cartCollection.doc(existingItem.id).update({
          'quantity': existingItem.quantity + 1,
        });
      } else {
        await cartCollection.add({
          'foodItemId': item.id,
          'quantity': 1,
          'selectedCafe': ?selectedCafe,
        });
      }
    } catch (e) {
      debugPrint('[CartService] Error adding to cart: $e');
    }
  }

  void removeFromCart(FoodItem item) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || item.id.isEmpty) return;

    final cartCollection = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('cart');

    final existingIndex = _cartItems.indexWhere(
      (element) => element.foodItem.id == item.id,
    );

    try {
      if (existingIndex >= 0) {
        final existingItem = _cartItems[existingIndex];
        if (existingItem.quantity > 1) {
          await cartCollection.doc(existingItem.id).update({
            'quantity': existingItem.quantity - 1,
          });
        } else {
          await cartCollection.doc(existingItem.id).delete();
        }
      }
    } catch (e) {
      debugPrint('[CartService] Error removing from cart: $e');
    }
  }

  void deleteFromCart(FoodItem item) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || item.id.isEmpty) return;

    final cartCollection = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('cart');

    final existingIndex = _cartItems.indexWhere(
      (element) => element.foodItem.id == item.id,
    );

    try {
      if (existingIndex >= 0) {
        final existingItem = _cartItems[existingIndex];
        await cartCollection.doc(existingItem.id).delete();
      }
    } catch (e) {
      debugPrint('[CartService] Error deleting from cart: $e');
    }
  }

  void clearCart() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final cartCollection = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('cart');

    try {
      final snapshot = await cartCollection.get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[CartService] Error clearing cart: $e');
    }
  }

  void placeOrder() {
    if (_cartItems.isEmpty) return;

    final newOrderId =
        'CB-${1000 + _orders.length + (DateTime.now().millisecond % 9000)}';
    final newOrder = FoodOrder(
      orderId: newOrderId,
      items: List.from(_cartItems),
      totalAmount: totalAmount,
      orderTime: DateTime.now(),
      status: OrderStatus.preparing,
    );

    _orders.insert(0, newOrder);
    clearCart();

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

  @override
  void dispose() {
    _cancelCartSubscription();
    _authSubscription?.cancel();
    super.dispose();
  }
}
