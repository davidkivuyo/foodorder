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

  /// Deterministic document ID of the cart serialization lock. Every cart
  /// add writes this document inside its transaction so concurrent adds from
  /// different cafes conflict on it (Firestore only aborts on overlapping
  /// writes) instead of committing a mixed-cafe cart. It carries no
  /// foodItemId (so the cart stream and persisted-cafe checks ignore it, and
  /// clearCart removes it naturally) plus a `cafe` marker — the cart's
  /// effective cafe, written transactionally with every add — so the one-cafe
  /// check inside an add transaction sees the cafe of any concurrent add that
  /// committed after the outer query snapshot. NOTE: the ID must NOT begin or
  /// end with a double underscore (reserved by Firestore — INVALID_ARGUMENT).
  static const String _cartLockDocId = '_cart_lock_';

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

    // One cafe per order against the PERSISTED cart: a queued op whose cafe
    // conflicts with the cart's current cafe is stale and can never be
    // applied — drop it rather than retrying forever.
    final incomingCafe = _resolveCafe(selectedCafe, foodItem) ?? '';
    final ownerUserId = op.ownerUserId;
    if (ownerUserId != null &&
        await _persistedCartConflict(ownerUserId, incomingCafe) != null) {
      AppLog.d(
        '[CartService] Dropping queued cart_add ${op.id}: persisted cart '
        'holds a different cafe (one cafe per order)',
      );
      return true;
    }

    return await _directAddToCart(foodItem, selectedCafe: selectedCafe, quantity: qty);
  }

  // ---------- Cart Operations ----------

  /// Returns the name of a cafe already represented in the cart that would
  /// conflict with adding [item], or null when the add is allowed.
  ///
  /// One cafe per order: a cart may only hold items from a single cafe. The
  /// effective cafe is resolved exactly like the add path ([_resolveCafe] →
  /// [_persistedCafeOf]/[_conflictInDocs]): a single-cafe item without an
  /// explicit selection is its canonical cafe, while a multi-cafe item
  /// without a selection is cafeless ('' — never its joined displayCafe
  /// list). An empty cart never conflicts.
  String? cafeConflictWithCart(String? selectedCafe, FoodItem item) {
    if (_cartItems.isEmpty) return null;
    final incomingCafe = _resolveCafe(selectedCafe, item) ?? '';
    for (final cartItem in _cartItems) {
      // Mirror the persisted classification (_persistedCafeOf): the stored
      // selectedCafe is the item's effective cafe, '' when cafeless.
      final cartCafe = cartItem.selectedCafe?.trim() ?? '';
      if (cartCafe != incomingCafe) {
        return cartCafe;
      }
    }
    return null;
  }

  /// Effective cafe of a persisted cart document's data; '' for cafeless
  /// items. Mirrors [CartItem.displayCafe] for the fields actually persisted
  /// (items are stored with a resolved selectedCafe).
  String _persistedCafeOf(Map<String, dynamic> data) =>
      (data['selectedCafe'] as String? ?? '').trim();

  /// Resolve a cart item's effective cafe ONCE so the offline cart item, the
  /// queued op and the persisted document all agree. A null/empty selection
  /// falls back to the item's single canonical cafe (e.g. 'Cafe A'); a
  /// genuinely cafeless item — or one with no single canonical cafe — keeps
  /// null so it is stored and classified as cafeless.
  String? _resolveCafe(String? selectedCafe, FoodItem item) {
    final stored = selectedCafe;
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    if (item.availableCafes.length == 1) return item.availableCafes.first;
    return null;
  }

  /// Returns the effective cafe of the first persisted cart document that
  /// conflicts with [incomingCafe] ('' for a cafeless conflict), or null
  /// when none does. Non-item documents (e.g. the serialization lock, which
  /// has no foodItemId) are ignored.
  String? _conflictInDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String incomingCafe,
  ) {
    for (final doc in docs) {
      final data = doc.data();
      if (data['foodItemId'] == null) continue;
      final cafe = _persistedCafeOf(data);
      if (cafe != incomingCafe) return cafe;
    }
    return null;
  }

  /// One-cafe-per-order check against the PERSISTED cart (not the local
  /// [_cartItems], which may be stale or empty on the queue-replay path).
  /// Returns the conflicting cafe, or null when the persisted cart holds no
  /// conflicting item. A read failure returns null — the write path re-checks
  /// inside its own retry loop.
  Future<String?> _persistedCartConflict(
    String userId,
    String incomingCafe,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('cart')
          .get();
      return _conflictInDocs(snapshot.docs, incomingCafe);
    } on Exception {
      return null;
    }
  }

  /// Add an item to the cart.
  ///
  /// Validates that [quantity] is positive (> 0) before writing to Firestore.
  /// Returns `true` on success, `false` when the user is not authenticated,
  /// the item ID is empty, the item is unavailable, [quantity] is invalid,
  /// the item is from a different cafe than the items already in the cart
  /// (one cafe per order), or a Firestore write error occurs.
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

    // Resolve the effective cafe ONCE so the offline cart item, the queued
    // op and the persisted document all store the same value: a single-cafe
    // item added without an explicit selection is stored under its canonical
    // cafe, never as null.
    final resolvedCafe = _resolveCafe(selectedCafe, item);

    // ── Guard: one cafe per order ──────────────────────────────────────
    // Blocks mixing cafes in a single order (online and offline paths both
    // pass through this guard). The backend placeOrder callable re-validates
    // the same rule server-side.
    final conflictingCafe = cafeConflictWithCart(resolvedCafe, item);
    if (conflictingCafe != null) {
      AppLog.d(
        '[CartService] Cannot add ${item.title}: cart already has items '
        'from $conflictingCafe (one cafe per order)',
      );
      return false;
    }

    if (!ConnectivityService().isOnline) {
      final existingIndex = _cartItems.indexWhere(
        (element) =>
            element.foodItem.id == item.id &&
            element.selectedCafe == resolvedCafe,
      );
      if (existingIndex >= 0) {
        _cartItems[existingIndex].quantity += quantity;
      } else {
        _cartItems.add(
          CartItem(
            id: '${item.id}_${resolvedCafe ?? ''}',
            foodItem: item,
            quantity: quantity,
            selectedCafe: resolvedCafe,
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
            'selectedCafe': resolvedCafe,
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
      selectedCafe: resolvedCafe,
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

    // Resolve the effective cafe once (see _resolveCafe) so the composite
    // key, legacy-document matching and the persisted selectedCafe all agree
    // with the one-cafe classification (_persistedCafeOf/_conflictInDocs
    // observe the same value on subsequent adds).
    final resolvedCafe = _resolveCafe(selectedCafe, item);
    final compositeKey = '${item.id}_${resolvedCafe ?? ''}';
    final compositeDocRef = cartCollection.doc(compositeKey);
    final lockDocRef = cartCollection.doc(_cartLockDocId);
    final incomingCafe = resolvedCafe ?? '';

    try {
      // Bounded retries: a concurrent add that commits between our read and
      // our transaction forces a write conflict on the shared lock document
      // (every add writes it), aborting the transaction. maxAttempts: 1
      // keeps the SDK from re-committing blindly on retry — we own the retry
      // loop so the transaction-fresh one-cafe check re-runs.
      for (int attempt = 0; attempt < 3; attempt++) {
        // Outer snapshot: used only to discover the legacy document and the
        // set of cart documents to re-read transaction-fresh. The one-cafe
        // decision itself happens INSIDE the transaction (see below) — this
        // snapshot may already be stale by the time the transaction runs.
        final snapshot = await cartCollection.get();

        // ── Legacy document (auto-generated ID) for this (item, cafe) ──
        // Any document whose ID differs from compositeKey is a legacy doc.
        final legacyDoc = snapshot.docs.where((d) =>
            d.id != compositeKey &&
            d.data()['foodItemId'] == item.id &&
            d.data()['selectedCafe'] == resolvedCafe).firstOrNull;

        try {
          return await _firestore.runTransaction(
            (txn) async {
              // All reads must precede all writes (Firestore requirement).
              //
              // One cafe per order — validated from TRANSACTION-FRESH reads,
              // not the stale outer snapshot. A concurrent add that commits
              // between the outer query and this transaction would otherwise
              // be invisible to the check (and with an empty read set the
              // transaction would not abort), letting a mixed-cafe cart
              // through. Re-reading every known cart document makes any
              // concurrent change to them abort this transaction (→ retry),
              // and the lock document's cafe marker represents adds that
              // committed after the outer query entirely.
              final lockSnap = await txn.get(lockDocRef);
              final freshCafes = <String>{};
              for (final doc in snapshot.docs) {
                if (doc.id == _cartLockDocId) continue;
                final fresh = await txn.get(doc.reference);
                if (!fresh.exists) continue; // removed concurrently
                final data = fresh.data();
                if (data == null || data['foodItemId'] == null) continue;
                freshCafes.add((data['selectedCafe'] as String? ?? '').trim());
              }
              final markerCafe = lockSnap.exists
                  ? (lockSnap.data()?['cafe'] as String? ?? '').trim()
                  : null;
              final conflictingCafe = freshCafes
                      .where((c) => c != incomingCafe)
                      .firstOrNull ??
                  (markerCafe != null && markerCafe != incomingCafe
                      ? markerCafe
                      : null);
              if (conflictingCafe != null) {
                AppLog.d(
                  '[CartService] Refused add of ${item.title}: persisted '
                  'cart holds $conflictingCafe (one cafe per order)',
                );
                return false; // rejected — no writes, no retry needed
              }

              bool migrateLegacy = false;
              int legacyQty = 0;
              if (legacyDoc != null) {
                final legacySnapshot = await txn.get(legacyDoc.reference);
                if (legacySnapshot.exists) {
                  migrateLegacy = true;
                  legacyQty =
                      (legacySnapshot.data()!['quantity'] as num?)?.toInt() ?? 0;
                }
                // Missing legacy doc → already migrated by a concurrent
                // call; just apply the incoming quantity below.
              }

              // Serialization point: every add writes the same lock
              // document (with the cart's effective cafe), so concurrent
              // adds from different cafes conflict here instead of
              // committing a mixed-cafe cart.
              txn.set(lockDocRef, {
                'cafe': incomingCafe,
                'lockedAt': FieldValue.serverTimestamp(),
              });

              txn.set(compositeDocRef, {
                'foodItemId': item.id,
                'quantity': FieldValue.increment(
                  migrateLegacy ? legacyQty + quantity : quantity,
                ),
                'selectedCafe': resolvedCafe,
              }, SetOptions(merge: true));

              if (migrateLegacy) {
                txn.delete(legacyDoc!.reference);
              }
              return true;
            },
            maxAttempts: 1,
          );
        } on Exception {
          // Transaction conflict (a concurrent add won the lock or modified
          // a document we read) — re-read the persisted cart and re-run the
          // transaction-fresh check before retrying.
          if (attempt >= 2) rethrow;
        }
      }
      // Unreachable: the loop returns on success or rethrows on the last
      // attempt (kept for Dart's flow analysis).
      return false;
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

    // Resolve the effective cafe the same way addToCart does, so removing
    // without an explicit selection finds a single-cafe item stored under
    // its canonical cafe (consistent implicit-cafe resolution).
    final resolvedCafe = _resolveCafe(selectedCafe, item);
    final existingIndex = _cartItems.indexWhere(
      (element) =>
          element.foodItem.id == item.id &&
          element.selectedCafe == resolvedCafe,
    );

    try {
      if (existingIndex >= 0) {
        final existingItem = _cartItems[existingIndex];
        if (existingItem.quantity > 1) {
          await cartCollection.doc(existingItem.id).update({
            'quantity': existingItem.quantity - 1,
          });
          // Optimistic local update (mirrors the offline add path); the cart
          // stream re-syncs from Firestore and stays consistent. Re-locate
          // by predicate so a concurrent stream sync can't leave a stale
          // index.
          final current = _cartItems.indexWhere(
            (element) =>
                element.foodItem.id == item.id &&
                element.selectedCafe == resolvedCafe,
          );
          if (current >= 0) _cartItems[current].quantity -= 1;
        } else {
          await cartCollection.doc(existingItem.id).delete();
          _cartItems.removeWhere(
            (element) =>
                element.foodItem.id == item.id &&
                element.selectedCafe == resolvedCafe,
          );
        }
        AnalyticsService.instance.logEvent(AnalyticsEvent.removedFromCart);
        notifyListeners();
      }
    } on Exception catch (e) {
      AppLog.e('[CartService] Error removing from cart', e);
    }
    await _syncCartLockMarker();
  }

  Future<void> deleteFromCart(FoodItem item, {String? selectedCafe}) async {
    final userId = _currentUserId;
    if (userId == null || item.id.isEmpty) return;

    final cartCollection = _firestore
        .collection('users')
        .doc(userId)
        .collection('cart');

    // Resolve the effective cafe the same way addToCart does (see
    // removeFromCart for the rationale — consistent implicit-cafe
    // resolution).
    final resolvedCafe = _resolveCafe(selectedCafe, item);
    final existingIndex = _cartItems.indexWhere(
      (element) =>
          element.foodItem.id == item.id &&
          element.selectedCafe == resolvedCafe,
    );

    try {
      if (existingIndex >= 0) {
        final existingItem = _cartItems[existingIndex];
        await cartCollection.doc(existingItem.id).delete();
        // Optimistic local update (mirrors the offline add path); the cart
        // stream re-syncs from Firestore and stays consistent. Re-locate by
        // predicate so a concurrent stream sync can't leave a stale index.
        _cartItems.removeWhere(
          (element) =>
              element.foodItem.id == item.id &&
              element.selectedCafe == resolvedCafe,
        );
        AnalyticsService.instance.logEvent(AnalyticsEvent.removedFromCart);
        notifyListeners();
      }
    } on Exception catch (e) {
      AppLog.e('[CartService] Error deleting from cart', e);
    }
    await _syncCartLockMarker();
  }

  /// Keep the serialization lock's cafe marker consistent with the cart's
  /// remaining items after a removal. The marker is written transactionally
  /// by every add; without this sync, emptying a cart would leave a stale
  /// marker that wrongly blocks a later add of a different cafe.
  Future<void> _syncCartLockMarker() async {
    final userId = _currentUserId;
    if (userId == null) return;
    final cartCollection = _firestore
        .collection('users')
        .doc(userId)
        .collection('cart');
    try {
      final snapshot = await cartCollection.get();
      final itemCafes = <String>{};
      for (final doc in snapshot.docs) {
        if (doc.id == _cartLockDocId) continue;
        final data = doc.data();
        if (data['foodItemId'] == null) continue;
        itemCafes.add((data['selectedCafe'] as String? ?? '').trim());
      }
      final lockRef = cartCollection.doc(_cartLockDocId);
      if (itemCafes.isEmpty) {
        await lockRef.delete();
      } else {
        // Invariant: all remaining items share one effective cafe.
        await lockRef.set({
          'cafe': itemCafes.first,
          'lockedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } on Exception catch (e) {
      AppLog.e('[CartService] Error syncing cart lock marker', e);
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

    // Availability is intentionally NOT pre-checked here: the placeOrder
    // callable re-checks every item authoritatively inside its transaction
    // and returns unavailableFood, which the cart sheet already surfaces
    // with a user-friendly message. A client-side pre-check would duplicate
    // those reads on every checkout attempt (§13 — rely on callable error
    // codes for user messaging).

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

      // Count aggregation: only the number matters for the limit check, and
      // the callable re-verifies inside its transaction anyway — no need to
      // download the active order documents themselves.
      final activeCount = await _firestore
          .collection('orders')
          .where('studentId', isEqualTo: userId)
          .where('status', whereIn: [
            for (final status in OrderStatus.activeOrderStatuses)
              status.toShortString(),
          ])
          .count()
          .get();
      if ((activeCount.count ?? 0) >= limit) {
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

  @override
  void dispose() {
    _cancelCartSubscription();
    _authSubscription?.cancel();
    super.dispose();
  }
}
