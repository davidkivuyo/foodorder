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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/food_data.dart';
import 'app_log.dart';

/// Maximum number of favourite food IDs to cache.
const int kMaxFavoriteIds = 5;

/// Service that manages the "Your Favourites" feature.
///
/// Responsibilities:
/// - Calculate favourite rankings from collected order history
/// - Cache the top-5 food IDs in the user's Firestore document
/// - Provide a stream of current favourite [FoodItem]s
/// - Automatically recalculate when an order transitions to COLLECTED
///
/// Business logic is kept out of UI widgets.
class FavoriteService {
  // Singleton pattern to share state and avoid duplicate listeners.
  static final FavoriteService _instance = FavoriteService._internal();
  factory FavoriteService() => _instance;
  FavoriteService._internal() {
    // Listen for auth changes to manage the orders listener independently
    // from any active stream subscriptions.  This ensures collections are
    // processed even when no UI widget is actively watching favourites,
    // and avoids setting up the listener as a side-effect of calling
    // favoriteFoodsStream().
    _authSubscription = _auth.authStateChanges().listen((user) {
      final uid = user?.uid;
      if (uid != null) {
        _ensureRecalculationListener(uid);
      } else {
        // User logged out — tear down everything.
        _cancelFoodStream();
        _ordersSubscription?.cancel();
        _ordersSubscription = null;
        _listenedUserId = null;
      }
    });
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot>? _ordersSubscription;
  String? _listenedUserId;

  /// Tracks the last known status of each order document so we can detect
  /// true transitions to COLLECTED vs. post-collection modifications.
  final Map<String, String?> _previousOrderStatuses = {};

  /// Cached combined stream so multiple callers share one set of subscriptions.
  Stream<List<FoodItem>>? _cachedFavoriteStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  final List<StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
      _foodSubs = [];

  /// Dispose all active subscriptions.
  void dispose() {
    _authSubscription?.cancel();
    _ordersSubscription?.cancel();
    _ordersSubscription = null;
    _listenedUserId = null;
    _previousOrderStatuses.clear();
    _cancelFoodStream();
  }

  void _cancelFoodStream() {
    _cachedFavoriteStream = null;
    _userDocSub?.cancel();
    _userDocSub = null;
    for (final sub in _foodSubs) {
      sub.cancel();
    }
    _foodSubs.clear();
  }

  // ── Public API ───────────────────────────────────────────────────

  /// Returns a live stream of favourite [FoodItem]s for the current user.
  ///
  /// The stream emits a new list whenever the cached favourite IDs change
  /// or the underlying food items are updated in Firestore.
  /// Deleted and unavailable items are skipped gracefully.
  /// Returns a live stream of favourite [FoodItem]s for the current user.
  ///
  /// The stream emits a new list whenever the cached favourite IDs change
  /// or the underlying food items are updated in Firestore.
  /// Deleted and unavailable items are skipped gracefully.
  /// The stream is cached so multiple callers share one set of Firestore
  /// subscriptions.
  Stream<List<FoodItem>> favoriteFoodsStream() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream.value([]);

    // Return the cached stream if already set up for this session.
    if (_cachedFavoriteStream != null) return _cachedFavoriteStream!;

    _cachedFavoriteStream = _buildFavoriteStream(userId);
    return _cachedFavoriteStream!;
  }

  /// Builds the combined stream.  Listens to the user doc for favourite ID
  /// changes and subscribes to each favourite food item via snapshots so
  /// live updates (e.g. availability toggle) are reflected automatically.
  Stream<List<FoodItem>> _buildFavoriteStream(String userId) {
    final controller = StreamController<List<FoodItem>>.broadcast();

    // Helper: read all current favourite IDs, preserving order, and emit.
    void emitCurrentFoods(List<String> ids) async {
      final foods = <FoodItem>[];
      for (final id in ids) {
        try {
          final doc = await _firestore
              .collection('food_items')
              .doc(id)
              .get();
          if (doc.exists && doc.data() != null) {
            final item = FoodItem.fromMap(doc.data()!, id: id);
            if (item.available) {
              foods.add(item);
            }
          }
        } on Exception catch (_) {
          // Skip on error — graceful degradation.
        }
      }
      if (!controller.isClosed) controller.add(foods);
    }

    // Set up food item subscriptions for a new set of favourite IDs.
    void setupFoodListeners(List<String> ids) {
      // Cancel old food subscriptions.
      for (final sub in _foodSubs) {
        sub.cancel();
      }
      _foodSubs.clear();

      if (ids.isEmpty) {
        if (!controller.isClosed) controller.add([]);
        return;
      }

      // Subscribe to each favourite food item so that availability
      // or detail changes re-emit the stream automatically.
      for (final id in ids) {
        final sub = _firestore
            .collection('food_items')
            .doc(id)
            .snapshots()
            .listen((_) => emitCurrentFoods(ids));
        _foodSubs.add(sub);
      }

      // Emit initial state.
      emitCurrentFoods(ids);
    }

    // Listen to the user doc for changes to the cached favourite IDs.
    _userDocSub = _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) {
        if (!controller.isClosed) controller.add([]);
        return;
      }

      final favoriteIds =
          (snapshot.data()?['favoriteMenu'] as List<dynamic>?)
                  ?.whereType<String>()
                  .where((id) => id.isNotEmpty)
                  .toList() ??
              [];

      setupFoodListeners(favoriteIds);
    });

    // Clean up all subscriptions when the stream is cancelled.
    controller.onCancel = () {
      _userDocSub?.cancel();
      _userDocSub = null;
      for (final sub in _foodSubs) {
        sub.cancel();
      }
      _foodSubs.clear();
      _cachedFavoriteStream = null;
    };

    return controller.stream;
  }

  /// Force recalculation of favourites based on collected order history.
  ///
  /// Call this when an order transitions to COLLECTED.
  /// This is a no-op if [userId] is null (not authenticated).
  Future<void> recalculateFavorites({String? userId}) async {
    final uid = userId ?? _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final foodIds = await _calculateFavoriteIds(uid);
      await _cacheFavoriteIds(uid, foodIds);
    } on Exception catch (e) {
      AppLog.e('[FavoriteService] Recalculation error', e);
    }
  }

  // ── Internal: ranking engine ─────────────────────────────────────

  /// Query all COLLECTED orders for [userId] and return the top-5 food IDs
  /// ranked by (frequency desc, most recent collection desc).
  Future<List<String>> _calculateFavoriteIds(String userId) async {
    final snapshot = await _firestore
        .collection('orders')
        .where('studentId', isEqualTo: userId)
        .where('status', isEqualTo: 'COLLECTED')
        .orderBy('updatedAt', descending: true)
        .get();

    // Count frequency of each food item and track most recent collection.
    final Map<String, int> frequency = {};
    final Map<String, DateTime> latestCollection = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      // Runtime type check: items must be a List; skip malformed docs.
      final rawItems = data['items'];
      final items = (rawItems is List) ? rawItems : <dynamic>[];
      // Use a distant-past fallback so missing timestamps lose
      // tie-breaks instead of winning them.
      final updatedAt = _parseTimestamp(data['updatedAt']) ?? DateTime(2000);

      for (final item in items) {
        if (item is! Map) continue;
        // Runtime type check: food ID must be a String; skip malformed items.
        final rawFoodItemId = item['foodItemId'];
        final rawId = item['id'];
        final foodId = (rawFoodItemId is String)
            ? rawFoodItemId
            : (rawId is String ? rawId : null);
        if (foodId == null || foodId.isEmpty) continue;

        frequency[foodId] = (frequency[foodId] ?? 0) + 1;

        // Keep the most recent collection date for tie-breaking.
        final existing = latestCollection[foodId];
        if (existing == null || updatedAt.isAfter(existing)) {
          latestCollection[foodId] = updatedAt;
        }
      }
    }

    if (frequency.isEmpty) return [];

    // Sort: frequency desc, then latest collection desc.
    final sorted = frequency.keys.toList()
      ..sort((a, b) {
        final freqCompare = (frequency[b] ?? 0).compareTo(frequency[a] ?? 0);
        if (freqCompare != 0) return freqCompare;

        final dateA = latestCollection[a] ?? DateTime(2000);
        final dateB = latestCollection[b] ?? DateTime(2000);
        return dateB.compareTo(dateA);
      });

    return sorted.take(kMaxFavoriteIds).toList();
  }

  /// Last persisted favourite list per user — used to skip redundant writes.
  final Map<String, List<String>> _lastCachedIds = {};

  /// Persist the top-5 favourite food IDs to the user's Firestore document.
  ///
  /// Sanitises the list before writing:
  /// - Filters out non-string values (belt-and-suspenders type safety)
  /// - Filters out empty strings
  /// - Caps at [kMaxFavoriteIds]
  ///
  /// Phase 13 (write optimization): if the sanitised list is unchanged from
  /// the last persisted value, no Firestore write is performed at all.
  Future<void> _cacheFavoriteIds(String userId, List<String> ids) async {
    final sanitised = ids
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .take(kMaxFavoriteIds)
        .toList();

    // Skip the write entirely when nothing changed — avoids unnecessary
    // server timestamp churn and write costs on every recalculation.
    final previous = _lastCachedIds[userId];
    if (_listEquals(previous, sanitised)) return;

    await _firestore.collection('users').doc(userId).set({
      'favoriteMenu': sanitised,
      'favoriteMenuUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _lastCachedIds[userId] = sanitised;
  }

  /// Listen for order transitions to COLLECTED and trigger recalculation.
  void _ensureRecalculationListener(String userId) {
    if (_listenedUserId == userId && _ordersSubscription != null) return;
    _ordersSubscription?.cancel();
    _previousOrderStatuses.clear();

    _listenedUserId = userId;
    _ordersSubscription = _firestore
        .collection('orders')
        .where('studentId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
          bool hasNewCollection = false;

          for (final change in snapshot.docChanges) {
            final docId = change.doc.id;
            final newStatus = change.doc.data()?['status'] as String?;

            switch (change.type) {
              case DocumentChangeType.added:
                // Initial load or a new order — record status, never trigger.
                _previousOrderStatuses[docId] = newStatus;

              case DocumentChangeType.modified:
                final oldStatus = _previousOrderStatuses[docId];
                // Only trigger if status genuinely changed TO collected.
                if (oldStatus != 'COLLECTED' && newStatus == 'COLLECTED') {
                  hasNewCollection = true;
                }
                _previousOrderStatuses[docId] = newStatus;

              case DocumentChangeType.removed:
                _previousOrderStatuses.remove(docId);
            }
          }

          if (hasNewCollection) {
            recalculateFavorites(userId: userId);
          }
        });
  }

  // ── Helpers ──────────────────────────────────────────────────────

  /// Shallow list equality used to detect unchanged favourite lists.
  bool _listEquals(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return (value as dynamic).toDate() as DateTime;
    } on Exception catch (_) {}
    return null;
  }
}
