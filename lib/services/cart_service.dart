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

  /// Incremented on each snapshot so overlapping async syncs don't apply stale results.
  int _cartSyncGeneration = 0;

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
        _cartSyncGeneration++; // Invalidate in-flight syncs from the old user.
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
          // Capture the generation BEFORE starting the async work so that
          // a newer snapshot that arrives while this sync is in flight will
          // have a higher generation, making this one a no-op on completion.
          final capturedGeneration = ++_cartSyncGeneration;
          await _syncCartItems(snapshot, generation: capturedGeneration);
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
  ///
  /// If [generation] is provided and is stale (older than the current
  /// [_cartSyncGeneration]), the sync is skipped to prevent older async
  /// results from overwriting newer ones.
  Future<void> _syncCartItems(
    QuerySnapshot snapshot, {
    int? generation,
  }) async {
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

    // Discard this sync if a newer snapshot has already been processed.
    if (generation != null && generation != _cartSyncGeneration) return;

    _cartItems.clear();
    _cartItems.addAll(updatedItems);
    notifyListeners();
  }

  void _cancelCartSubscription() {
    _cartSubscription?.cancel();
    _cartSubscription = null;
  }

  // ---------- Cart Operations ----------

  Future<void> addToCart(FoodItem item, {String? selectedCafe}) async {
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

  Future<void> removeFromCart(FoodItem item) async {
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

  Future<void> deleteFromCart(FoodItem item) async {
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
  ///
  /// The order is written inside a Firestore transaction that re-reads
  /// the current `available` field of every food item.  If any item is
  /// unavailable at that moment, the transaction is aborted and `null`
  /// is returned — the UI-level check is only a hint; this is the
  /// authoritative enforcement point.
  Future<String?> placeOrder({
    GeoPoint? cafeLocation,
    String? cafeId,
    double? distanceMeters,
    int? pickupWindowMinutes,
  }) async {
    if (_cartItems.isEmpty) return null;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return null;

    // Build the serialised order data before the transaction — we need
    // a snapshot of _cartItems at this point; any stock changes that
    // happen during the transaction will be caught by the reads inside.
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = timestamp % 9000;
    final newOrderId = 'CB-${1000 + randomSuffix}';

    final displayName = _cachedUserName.isNotEmpty
        ? _cachedUserName
        : (FirebaseAuth.instance.currentUser?.displayName ?? 'Student');
    final hasDistanceData = cafeLocation != null && distanceMeters != null;
    final itemsSnapshot = List<CartItem>.from(_cartItems);
    final itemsTotal = itemsSnapshot.fold<double>(
      0.0, (total, item) => total + item.foodItem.price * item.quantity,
    );

    final newOrder = FoodOrder(
      orderId: newOrderId,
      userId: userId,
      userName: displayName,
      items: itemsSnapshot,
      totalAmount: itemsTotal,
      orderTime: DateTime.now(),
      status: OrderStatus.pending,
      pickupWindowMinutes: pickupWindowMinutes ?? 20,
      distanceCalculated: hasDistanceData,
      cafeLocation: cafeLocation,
      cafeId: cafeId,
      distanceMeters: distanceMeters,
    );

    final orderData = newOrder.toFirestore();
    final firestore = FirebaseFirestore.instance;

    try {
      await firestore.runTransaction((transaction) async {
        // ── 1. Re-read every food item's availability inside the transaction ──
        final unavailableItems = <String>[];

        for (final item in itemsSnapshot) {
          final foodRef =
              firestore.collection('food_items').doc(item.foodItem.id);
          final foodSnapshot = await transaction.get(foodRef);

          if (!foodSnapshot.exists) {
            unavailableItems.add(item.foodItem.title);
            continue;
          }

          final foodData =
              foodSnapshot.data();
          final available =
              (foodData?['available'] as bool?) ?? true;

          if (!available) {
            unavailableItems.add(item.foodItem.title);
          }
        }

        // If any item is unavailable, abort — Firestore throws
        // an AbortedException which we catch below as a failure.
        if (unavailableItems.isNotEmpty) {
          throw FirebaseException(
            plugin: 'firestore',
            code: 'failed-precondition',
            message:
                'Some items are no longer available: ${unavailableItems.join(', ')}',
          );
        }

        // ── 2. All items pass — atomically write the order ──
        transaction.set(
          firestore.collection('orders').doc(newOrderId),
          orderData,
        );
      });

      // Transaction committed successfully — now clear the cart
      // (outside the transaction because the cart is a subcollection
      // of a document we didn't read within the transaction).
      await clearCart();

      debugPrint('[CartService] Order placed successfully: $newOrderId');
      return newOrderId;
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        debugPrint('[CartService] Order rejected — unavailable items: $e');
      } else if (e.code == 'aborted') {
        debugPrint('[CartService] Transaction conflict; order not placed');
      } else {
        debugPrint('[CartService] Error placing order: $e');
      }
      return null;
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
