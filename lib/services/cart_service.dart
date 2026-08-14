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
import '../models/pickup_reliability.dart';
import '../models/sync_operation.dart';
import '../data/food_data.dart';
import 'analytics_service.dart';
import 'app_log.dart';
import 'connectivity_service.dart';
import 'order_placement_service.dart';
import 'performance_service.dart';
import 'sync_queue_service.dart';

class CartService extends ChangeNotifier {
  // Singleton pattern to share state across screens
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;

  FirebaseFirestore _firestore;

  /// When non-null, overrides [FirebaseAuth.instance.currentUser.uid] for testing.
  /// Set by the [CartService.testing] constructor.
  String? _testingUserId;

  /// Injectable Phase E order-placement callable wrapper (null → shared
  /// [OrderPlacementService.instance], resolved lazily at call time so the
  /// singleton never touches Firebase during construction).
  final OrderPlacementService? _placementService;

  CartService._internal()
      : _firestore = FirebaseFirestore.instance,
        _placementService = null {
    _initAuthListener();
    _initSyncHandlers();
  }

  /// Testing constructor with injectable Firestore.
  ///
  /// [firestore] replaces [FirebaseFirestore.instance].
  /// [userId] replaces [FirebaseAuth.instance.currentUser.uid].
  /// Does NOT set up auth listeners -- the test manages auth state.
  CartService.testing({
    required this._firestore,
    required String userId,
    OrderPlacementService? placementService,
  })  : _testingUserId = userId,
        // Private fields cannot be initializing formals for named parameters.
        _placementService = placementService; // ignore: prefer_initializing_formals

  OrderPlacementService get _orderPlacement =>
      _placementService ?? OrderPlacementService.instance;

  /// Returns the current user ID from the testing override, or from
  /// FirebaseAuth if no override is active.
  String? get _currentUserId =>
      _testingUserId ?? FirebaseAuth.instance.currentUser?.uid;


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
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        _cachedUserName = data?['fullName'] as String? ?? '';
      }
    } on Exception catch (_) {}
    if (_cachedUserName.isEmpty) {
      _cachedUserName = user.displayName ?? 'Student';
    }
  }

  void _listenToCart(String userId) {
    _cancelCartSubscription();
    _cartSubscription = _firestore
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
        final foodDoc = await _firestore
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
      } on Exception catch (e) {
        AppLog.e('[CartService] Error refreshing food item ${item.foodItem.id}', e);
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
          final foodDoc = await _firestore
              .collection('food_items')
              .doc(foodItemId)
              .get();
          if (foodDoc.exists && foodDoc.data() != null) {
            foodItem = FoodItem.fromMap(foodDoc.data()!, id: foodDoc.id);
            _foodItemsCache[foodItemId] = foodItem;
          }
        } on Exception catch (e) {
          AppLog.e('[CartService] Error fetching food item $foodItemId', e);
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

  void _initSyncHandlers() {
    final queue = SyncQueueService();
    queue.registerHandler('cart_add', handleCartAddOp);
  }

  /// Executes a queued `cart_add` operation.
  ///
  /// Returns `true` when the operation was applied, or when it can never be
  /// applied because the item was permanently removed or is unavailable, so
  /// the queue can drop it. Transient failures are NOT swallowed: a failed
  /// FoodItem fetch propagates so [SyncQueueService] marks the operation for
  /// retry instead of treating it as a successful replay.
  @visibleForTesting
  Future<bool> handleCartAddOp(SyncOperation op) async {
    final itemId = op.payload['foodItemId'] as String?;
    final qty = (op.payload['quantity'] as num?)?.toInt() ?? 1;
    final selectedCafe = op.payload['selectedCafe'] as String?;
    if (itemId == null || itemId.isEmpty) return true;

    FoodItem? foodItem = _foodItemsCache[itemId];
    if (foodItem == null) {
      final doc = await _firestore.collection('food_items').doc(itemId).get();
      if (doc.exists && doc.data() != null) {
        foodItem = FoodItem.fromMap(doc.data()!, id: doc.id);
        _foodItemsCache[itemId] = foodItem;
      }
    }

    // Skip deleted or out-of-stock items gracefully.
    if (foodItem == null || !foodItem.available) return true;

    return await _directAddToCart(foodItem, selectedCafe: selectedCafe, quantity: qty);
  }

  // ---------- Cart Operations ----------

  /// Add an item to the cart.
  ///
  /// Validates that [quantity] is positive (> 0) before writing to Firestore.
  /// Returns `true` on success, `false` when the user is not authenticated,
  /// the item ID is empty, the item is unavailable, [quantity] is invalid,
  /// or a Firestore write error occurs.
  Future<bool> addToCart(FoodItem item, {String? selectedCafe, int quantity = 1}) async {
    // ── Guard: unauthenticated / invalid item ──────────────────────────
    final userId = _currentUserId;
    if (userId == null || item.id.isEmpty) return false;

    // ── Guard: unavailable item ────────────────────────────────────────
    if (!item.available) {
      AppLog.d('[CartService] Cannot add unavailable item: ${item.title}');
      return false;
    }

    // ── Guard: invalid quantity ────────────────────────────────────────
    if (quantity <= 0) {
      AppLog.d('[CartService] Cannot add item with invalid quantity: $quantity');
      return false;
    }

    if (!ConnectivityService().isOnline) {
      final existingIndex = _cartItems.indexWhere(
        (element) => element.foodItem.id == item.id && element.selectedCafe == selectedCafe,
      );
      if (existingIndex >= 0) {
        _cartItems[existingIndex].quantity += quantity;
      } else {
        _cartItems.add(
          CartItem(
            id: '${item.id}_${selectedCafe ?? ''}',
            foodItem: item,
            quantity: quantity,
            selectedCafe: selectedCafe,
          ),
        );
      }
      notifyListeners();

      await SyncQueueService().enqueue(
        SyncOperation(
          id: 'cart_add_${DateTime.now().millisecondsSinceEpoch}',
          type: 'cart_add',
          ownerUserId: userId,
          payload: {
            'foodItemId': item.id,
            'quantity': quantity,
            'selectedCafe': selectedCafe,
          },
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      AnalyticsService.instance.logEvent(
        AnalyticsEvent.addedToCart,
        params: {'item_count': quantity},
      );
      return true;
    }

    // The analytics event is emitted at the public entry point only — the
    // sync-queue replay path (_directAddToCart) must not double-count.
    final added = await _directAddToCart(
      item,
      selectedCafe: selectedCafe,
      quantity: quantity,
    );
    if (added) {
      AnalyticsService.instance.logEvent(
        AnalyticsEvent.addedToCart,
        params: {'item_count': quantity},
      );
    }
    return added;
  }

  Future<bool> _directAddToCart(FoodItem item, {String? selectedCafe, int quantity = 1}) async {
    final userId = _currentUserId;
    if (userId == null || item.id.isEmpty) return false;

    final cartCollection = _firestore
        .collection('users')
        .doc(userId)
        .collection('cart');

    final compositeKey = '${item.id}_${selectedCafe ?? ''}';
    final compositeDocRef = cartCollection.doc(compositeKey);

    try {
      // ── Look for a legacy document (auto-generated ID) for this (item, cafe) ──
      // Any document whose ID differs from compositeKey is a legacy doc.
      final docs = await cartCollection
          .where('foodItemId', isEqualTo: item.id)
          .where('selectedCafe', isEqualTo: selectedCafe)
          .get();

      final legacyDoc = docs.docs.where((d) => d.id != compositeKey).firstOrNull;

      if (legacyDoc != null) {
        // Migration path: use a transaction so the legacy-document read is
        // guarded by optimistic concurrency control — two concurrent calls
        // cannot both apply the legacy quantity.
        await _firestore.runTransaction((txn) async {
          final legacySnapshot = await txn.get(legacyDoc.reference);
          if (!legacySnapshot.exists) {
            // Already migrated by another concurrent call — just apply
            // the incoming quantity to the composite document.
            txn.set(compositeDocRef, {
              'foodItemId': item.id,
              'quantity': FieldValue.increment(quantity),
              'selectedCafe': selectedCafe,
            }, SetOptions(merge: true));
            return;
          }
          final legacyQty =
              (legacySnapshot.data()!['quantity'] as num?)?.toInt() ?? 0;
          txn.set(compositeDocRef, {
            'foodItemId': item.id,
            'quantity': FieldValue.increment(legacyQty + quantity),
            'selectedCafe': selectedCafe,
          }, SetOptions(merge: true));
          txn.delete(legacyDoc.reference);
        });
      } else {
        // Normal path: write to the canonical composite document.
        // FieldValue.increment makes the write atomic regardless of write ordering.
        await compositeDocRef.set({
          'foodItemId': item.id,
          'quantity': FieldValue.increment(quantity),
          'selectedCafe': selectedCafe,
        }, SetOptions(merge: true));
      }
      return true;
    } on Exception catch (e) {
      AppLog.e('[CartService] Error adding to cart', e);
      return false;
    }
  }

  Future<void> removeFromCart(FoodItem item, {String? selectedCafe}) async {
    final userId = _currentUserId;
    if (userId == null || item.id.isEmpty) return;

    final cartCollection = _firestore
        .collection('users')
        .doc(userId)
        .collection('cart');

    final existingIndex = _cartItems.indexWhere(
      (element) =>
          element.foodItem.id == item.id &&
          element.selectedCafe == selectedCafe,
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
        AnalyticsService.instance.logEvent(AnalyticsEvent.removedFromCart);
      }
    } on Exception catch (e) {
      AppLog.e('[CartService] Error removing from cart', e);
    }
  }

  Future<void> deleteFromCart(FoodItem item, {String? selectedCafe}) async {
    final userId = _currentUserId;
    if (userId == null || item.id.isEmpty) return;

    final cartCollection = _firestore
        .collection('users')
        .doc(userId)
        .collection('cart');

    final existingIndex = _cartItems.indexWhere(
      (element) =>
          element.foodItem.id == item.id &&
          element.selectedCafe == selectedCafe,
    );

    try {
      if (existingIndex >= 0) {
        final existingItem = _cartItems[existingIndex];
        await cartCollection.doc(existingItem.id).delete();
      }
    } on Exception catch (e) {
      AppLog.e('[CartService] Error deleting from cart', e);
    }
  }

  Future<void> clearCart() async {
    final userId = _currentUserId;
    if (userId == null) return;

    final cartCollection = _firestore
        .collection('users')
        .doc(userId)
        .collection('cart');

    try {
      final snapshot = await cartCollection.get();
      if (snapshot.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } on Exception catch (e) {
      AppLog.e('[CartService] Error clearing cart', e);
    }
  }

  /// Check whether the current user's account is suspended.
  ///
  /// Returns `true` when `accountStatus == 'SUSPENDED'`, meaning the
  /// student cannot place orders. The strike-count-based suspension was
  /// removed together with the automatic strike engine; account status is
  /// now the only client-side gate (mirrored by the Firestore rules).
  Future<bool> isAccountSuspended() async {
    final uid = _currentUserId;
    if (uid == null) return false;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .get();

      if (!doc.exists) return false;

      final data = doc.data()!;
      final accountStatus = data['accountStatus'] as String? ?? 'ACTIVE';

      return accountStatus == 'SUSPENDED';
    } on Exception catch (_) {
      return false;
    }
  }

  /// Place the current cart items as an order through the backend
  /// `placeOrder` callable.
  ///
  /// Optionally include [cafeLocation], [cafeId], [distanceMeters], and
  /// [pickupWindowMinutes] for the distance-aware pickup window.
  ///
  /// Student location is NEVER persisted to Firestore for privacy.
  /// Distance and pickup window are stored as anonymized values.
  ///
  /// Phase E — order creation is authoritative on the backend: the callable
  /// derives the student's active-order limit from the server-maintained
  /// reliability summary, counts active orders inside its own transaction
  /// and re-checks food availability before creating the order. The client
  /// pre-checks the limit (AGENTS.md §17) and availability as UX hints only;
  /// if the pre-check cannot run (e.g. offline) the callable still enforces
  /// everything server-side.
  Future<OrderPlacementResult> placeOrder({
    GeoPoint? cafeLocation,
    String? cafeId,
    double? distanceMeters,
    int? pickupWindowMinutes,
  }) async {
    if (_cartItems.isEmpty) {
      return (
        orderId: null,
        failure: OrderPlacementFailure.invalidPayload,
        activeOrderLimit: null,
      );
    }

    final userId = _currentUserId;
    if (userId == null) {
      return (
        orderId: null,
        failure: OrderPlacementFailure.unauthenticated,
        activeOrderLimit: null,
      );
    }

    // ── Phase 15: verified-email gate ───────────────────────────────────
    // Only email-verified accounts may place orders. This mirrors the
    // Firestore security-rule requirement (request.auth.token.email_verified)
    // and the router-level redirect, so ordering is blocked even if a
    // malicious client bypasses the UI.
    if (!(FirebaseAuth.instance.currentUser?.emailVerified ?? false)) {
      AppLog.w('[CartService] Order blocked — email not verified');
      return (
        orderId: null,
        failure: OrderPlacementFailure.invalidPayload,
        activeOrderLimit: null,
      );
    }

    // Build the serialised order payload — a plain JSON map, because
    // FieldValue server timestamps cannot cross the callable wire; the
    // backend writes createdAt/updatedAt itself.
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = timestamp % 9000;
    final newOrderId = 'CB-${1000 + randomSuffix}';

    final displayName = _cachedUserName.isNotEmpty
        ? _cachedUserName
        : 'Student';
    final hasDistanceData = cafeLocation != null && distanceMeters != null;
    final itemsSnapshot = List<CartItem>.from(_cartItems);
    final itemsTotal = itemsSnapshot.fold<double>(
      0.0, (total, item) => total + item.foodItem.price * item.quantity,
    );

    // Phase E §17 — pre-checkout explanation. The callable is the authority;
    // this only avoids attempting a checkout that would be rejected. When the
    // check itself fails (offline, quota, ...) we proceed rather than assume
    // anything about the limit.
    final precheck = await _checkActiveOrderLimit(userId);
    if (precheck != null) return precheck;

    // Phase E — availability pre-check (UX hint only; the callable re-checks
    // authoritatively inside its transaction and is the enforcement point).
    final unavailable = await _findUnavailableItems(itemsSnapshot);
    if (unavailable.isNotEmpty) {
      return (
        orderId: null,
        failure: OrderPlacementFailure.unavailableFood,
        activeOrderLimit: null,
      );
    }

    final payload = <String, dynamic>{
      'orderId': newOrderId,
      'studentId': userId,
      'userName': displayName,
      'items': itemsSnapshot
          .map(
            (item) => {
              'foodItemId': item.foodItem.id,
              'title': item.foodItem.title,
              'price': item.foodItem.price,
              'quantity': item.quantity,
              'image': item.foodItem.image,
              'selectedCafe': item.selectedCafe,
            },
          )
          .toList(),
      'foodIds': itemsSnapshot.map((item) => item.foodItem.id).toList(),
      'price': itemsTotal,
      'cafeId': cafeId,
      'cafeLocation': cafeLocation == null
          ? null
          : {
              'latitude': cafeLocation.latitude,
              'longitude': cafeLocation.longitude,
            },
      'distanceMeters': distanceMeters,
      'distanceCalculated': hasDistanceData,
      'pickupWindowMinutes': pickupWindowMinutes ?? 20,
    };

    // Phase 17 — checkout performance trace (stopped on every exit path).
    final checkoutTrace = PerformanceService.instance.startTrace(kTraceCheckout);
    try {
      final result = await _orderPlacement.placeOrder(payload);
      if (result.failure == null && result.orderId != null) {
        await clearCart();
        AppLog.d('[CartService] Order placed successfully: ${result.orderId}');
        AnalyticsService.instance.logEvent(
          AnalyticsEvent.orderPlaced,
          params: {'item_count': itemsSnapshot.length},
        );
      }
      return result;
    } finally {
      checkoutTrace?.stop();
    }
  }

  /// Phase E §17 — client-side pre-checkout gate.
  ///
  /// Reads the server-maintained restriction state from the user profile and
  /// counts active orders; returns an early [OrderPlacementResult] when the
  /// student is at their active-order limit, or null to proceed to the
  /// authoritative callable. Never blocks when the check itself fails.
  Future<OrderPlacementResult?> _checkActiveOrderLimit(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final summaryRaw = userDoc.exists
          ? (userDoc.data()?['pickupReliability'])
          : null;
      final summary = summaryRaw is Map
          ? PickupReliabilitySummary.fromMap(
              Map<String, dynamic>.from(summaryRaw),
            )
          : null;
      final limit = summary?.activeOrderLimit;
      if (limit == null) return null;

      final active = await _firestore
          .collection('orders')
          .where('studentId', isEqualTo: userId)
          .where('status', whereIn: [
            for (final status in OrderStatus.activeOrderStatuses)
              status.toShortString(),
          ])
          .get();
      if (active.size >= limit) {
        return (
          orderId: null,
          failure: OrderPlacementFailure.activeOrderLimit,
          activeOrderLimit: limit,
        );
      }
      return null;
    } on Exception {
      // Offline / query failure — proceed to the callable (authoritative).
      return null;
    }
  }

  /// Phase E — availability pre-check (UX hint).
  ///
  /// Returns the titles of cart items that are missing or marked unavailable.
  /// The `placeOrder` callable re-checks availability authoritatively inside
  /// its transaction, so a stale hint can never create an invalid order.
  Future<List<String>> _findUnavailableItems(List<CartItem> items) async {
    final unavailable = <String>[];
    try {
      for (final item in items) {
        final snapshot = await _firestore
            .collection('food_items')
            .doc(item.foodItem.id)
            .get();
        final exists = snapshot.exists;
        final available = (snapshot.data()?['available'] as bool?) ?? true;
        if (!exists || !available) {
          unavailable.add(item.foodItem.title);
        }
      }
    } on Exception catch (e) {
      AppLog.e('[CartService] Availability pre-check failed', e);
    }
    return unavailable;
  }

  @override
  void dispose() {
    _cancelCartSubscription();
    _authSubscription?.cancel();
    super.dispose();
  }
}
