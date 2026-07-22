// Copyright 2026 davidkivuyo, johnsonmushi, edwinkessy276-art, jugraki-art.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
  final Map<String, FoodItem> _foodItemsCache = {};

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot>? _cartSubscription;

  List<CartItem> get cartItems => List.unmodifiable(_cartItems);

  /// Cached user name used when placing orders.
  String _cachedUserName = '';

  /// Returns items in the cart whose food item is no longer available.
  List<CartItem> get outOfStockItems =>
      _cartItems.where((item) => !item.foodItem.available).toList();

  /// Whether any cart items are currently out of stock.
  bool get hasOutOfStockItems => _cartItems.any((item) => !item.foodItem.available);

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
        // Reset cached name so a different user's name is always fetched
        _resetCachedName();
        _cacheUserName(user);
        _listenToCart(user.uid);
      } else {
        _cancelCartSubscription();
        _cartItems.clear();
        notifyListeners();
      }
    });
  }

  void _resetCachedName() {
    _cachedUserName = '';
  }

  /// Fetch the current user's fullName from Firestore and cache it.
  Future<void> _cacheUserName(User user) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        _cachedUserName = data?['fullName'] as String? ?? '';
      }
    } catch (_) {}
    if (_cachedUserName.isEmpty) {
      _cachedUserName = user.displayName ?? 'Student';
    }
  }

  void _listenToCart(String userId) {
    _cancelCartSubscription();
    _cartSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('cart')
        .snapshots()
        .listen((snapshot) async {
          await _syncCartItems(snapshot);
        });
  }

  /// Re-fetches food item data for all cart items from Firestore.
  ///
  /// This ensures availability changes made by the admin (e.g., marking
  /// an item out of stock) are reflected immediately in the cart UI.
  Future<void> refreshCartItemAvailability() async {
    if (_cartItems.isEmpty) return;

    bool changed = false;
    for (final item in _cartItems) {
      try {
        final foodDoc = await FirebaseFirestore.instance
            .collection('food_items')
            .doc(item.foodItem.id)
            .get();
        if (foodDoc.exists && foodDoc.data() != null) {
          final freshItem =
              FoodItem.fromMap(foodDoc.data()!, id: foodDoc.id);
          // Update the cache
          _foodItemsCache[item.foodItem.id] = freshItem;
          // Check if availability actually changed
          if (freshItem.available != item.foodItem.available) {
            changed = true;
          }
          // Mutate the cart item's foodItem reference
          item.foodItem.available = freshItem.available;
        }
      } catch (e) {
        debugPrint(
          '[CartService] Error refreshing food item ${item.foodItem.id}: $e',
        );
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// Sync local cart state from a Firestore query snapshot.
  Future<void> _syncCartItems(QuerySnapshot snapshot) async {
    final List<CartItem> updatedItems = [];

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
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
  }

  void _cancelCartSubscription() {
    _cartSubscription?.cancel();
    _cartSubscription = null;
  }

  // ---------- Cart Operations ----------

  void addToCart(FoodItem item, {String? selectedCafe}) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || item.id.isEmpty) return;
    
    // Check if item is available before adding to cart
    if (!item.available) {
      debugPrint('[CartService] Cannot add unavailable item: ${item.title}');
      return;
    }

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
          'selectedCafe': selectedCafe,
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

  Future<void> clearCart() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final cartCollection = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('cart');

    try {
      final snapshot = await cartCollection.get();
      if (snapshot.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[CartService] Error clearing cart: $e');
    }
  }

  /// Check whether the current user's account is suspended.
  ///
  /// Check whether the current user's account is suspended.
  ///
  /// Returns `true` when `accountStatus == 'SUSPENDED'` or
  /// `strikeCount >= 2`, meaning the student cannot place orders.
  ///
  /// Phase 6: Derives percentage from strikeCount * 50.
  Future<bool> isAccountSuspended() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!doc.exists) return false;

      final data = doc.data()!;
      final accountStatus = data['accountStatus'] as String? ?? 'ACTIVE';
      final strikeCount =
          (data['strikeCount'] as num?)?.toInt() ?? 0;

      return accountStatus == 'SUSPENDED' || strikeCount >= 2;
    } catch (_) {
      return false;
    }
  }

  /// Place the current cart items as an order and save to Firestore.
  ///
  /// Optionally include [cafeLocation], [cafeId], [distanceMeters], and
  /// [pickupWindowMinutes] for the distance-aware pickup window.
  ///
  /// Student location is NEVER persisted to Firestore for privacy.
  /// Distance and pickup window are stored as anonymized values.
  Future<String?> placeOrder({
    GeoPoint? cafeLocation,
    String? cafeId,
    double? distanceMeters,
    int? pickupWindowMinutes,
  }) async {
    if (_cartItems.isEmpty) return null;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return null;

    // Generate a unique order ID
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = timestamp % 9000;
    final newOrderId = 'CB-${1000 + randomSuffix}';

    // Build the order document — use cached name or fallback to Firebase displayName
    final displayName = _cachedUserName.isNotEmpty
        ? _cachedUserName
        : (FirebaseAuth.instance.currentUser?.displayName ?? 'Student');
    final hasDistanceData = cafeLocation != null && distanceMeters != null;
    final newOrder = FoodOrder(
      orderId: newOrderId,
      userId: userId,
      userName: displayName,
      items: List.from(_cartItems),
      totalAmount: totalAmount,
      orderTime: DateTime.now(),
      status: OrderStatus.pending,
      pickupWindowMinutes: pickupWindowMinutes ?? 20,
      distanceCalculated: hasDistanceData,
      cafeLocation: cafeLocation,
      cafeId: cafeId,
      distanceMeters: distanceMeters,
    );

    try {
      // Save to Firestore under 'orders' collection with the generated ID
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(newOrderId)
          .set(newOrder.toFirestore());

      // Clear the cart after successful order placement
      await clearCart();

      debugPrint('[CartService] Order placed successfully: $newOrderId');
      return newOrderId;
    } catch (e) {
      debugPrint('[CartService] Error placing order: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _cancelCartSubscription();
    _authSubscription?.cancel();
    super.dispose();
  }
}
