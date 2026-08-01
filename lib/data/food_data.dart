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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FoodItem {
  final String id;
  final String image;
  final String title;
  final String titleLower;
  final String subtitle;
  final String description;
  final int price;
  final double rating;
  final String category;
  final List<String> availableCafes;
  final String time;
  final String section;
  bool available;
  final bool featured;
  final int quantity;
  final List<String> dietaryTags;
  final List<String> keywords;
  final List<String> searchPrefixes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Phase 12: Review aggregation fields
  final double averageRating;
  final int reviewCount;
  final Map<String, dynamic>? ratingDistribution;

  FoodItem({
    this.id = '',
    this.image = '',
    this.title = '',
    this.titleLower = '',
    this.subtitle = '',
    this.description = '',
    this.price = 0,
    this.rating = 4.5,
    this.category = '',
    this.availableCafes = const [],
    this.time = '',
    this.section = '',
    this.available = true,
    this.featured = false,
    this.quantity = 0,
    this.dietaryTags = const [],
    this.keywords = const [],
    this.searchPrefixes = const [],
    this.createdAt,
    this.updatedAt,
    this.averageRating = 0.0,
    this.reviewCount = 0,
    this.ratingDistribution,
  });

  factory FoodItem.fromMap(Map<String, dynamic> map, {String? id}) {
    // Parse timestamp fields that could be Timestamp, String, or null
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      // Firebase Timestamp has a toDate() method
      try {
        return (value as dynamic).toDate() as DateTime;
      } catch (_) {}
      return null;
    }

    // Parse price – the student app stores it as int, but we support
    // both int (cents) and double (dollars) from the admin form.
    int parsePrice(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.round();
      final parsed = double.tryParse(value?.toString() ?? '');
      return parsed != null ? parsed.round() : 0;
    }

    // Parse list fields that could be stored as List or be absent
    List<String> parseStringList(dynamic value) {
      if (value == null) return [];
      if (value is List) return value.map((e) => e.toString()).toList();
      return [];
    }

    // Parse rating distribution map
    Map<String, dynamic>? parseRatingDistribution(dynamic value) {
      if (value == null) return null;
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    return FoodItem(
      id: id ?? map['id'] ?? '',
      image: map['image'] ?? '',
      title: map['title'] ?? '',
      titleLower: map['titleLower'] ?? '',
      subtitle: map['subtitle'] ?? '',
      description: map['description'] ?? '',
      price: parsePrice(map['price']),
      rating: (map['rating'] ?? 4.5).toDouble(),
      category: map['category'] ?? '',
      availableCafes: parseStringList(map['availableCafes'] ?? map['cafes']),
      time: map['time'] ?? '',
      section: map['section'] ?? '',
      available: map['available'] ?? true,
      featured: map['featured'] ?? false,
      quantity: (() {
        final qty = map['quantity'];
        return qty is int ? qty : int.tryParse(qty?.toString() ?? '0') ?? 0;
      })(),
      dietaryTags: parseStringList(map['dietaryTags']),
      keywords: parseStringList(map['keywords']),
      searchPrefixes: parseStringList(map['searchPrefixes']),
      createdAt: parseTimestamp(map['createdAt']),
      updatedAt: parseTimestamp(map['updatedAt']),
      averageRating: (map['averageRating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (map['reviewCount'] as num?)?.toInt() ?? 0,
      ratingDistribution: parseRatingDistribution(map['ratingDistribution']),
    );
  }

  String get displayCafe => availableCafes.join(', ');

  /// Display‑friendly price in TZS (the value stored is in TZS).
  String get formattedPrice => '$price';

  /// Converts this [FoodItem] to a Firestore-compatible map.
  Map<String, dynamic> toMap() {
    return {
      'image': image,
      'title': title,
      'titleLower': titleLower,
      'subtitle': subtitle,
      'description': description,
      'price': price,
      'rating': rating,
      'category': category,
      'availableCafes': availableCafes,
      'time': time,
      'section': section,
      'available': available,
      'featured': featured,
      'quantity': quantity,
      'dietaryTags': dietaryTags,
      'keywords': keywords,
      'searchPrefixes': searchPrefixes,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  /// Builds the food item image from network (if URL) or local asset,
  /// with loading placeholder and a non-annoying error message on failure.
  Widget buildImage({
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    final bool isNetwork =
        image.startsWith('http://') || image.startsWith('https://');

    if (isNetwork) {
      return CachedNetworkImage(
        imageUrl: image,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (context, url, error) =>
            _buildErrorPlaceholder(width, height),
      );
    } else {
      return Image.asset(
        image,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) =>
            _buildErrorPlaceholder(width, height),
      );
    }
  }

  Widget _buildErrorPlaceholder(double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade100,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: Colors.grey.shade400,
            size: (width != null && width < 100) ? 24 : 36,
          ),
          if (width == null || width >= 100) ...[
            const SizedBox(height: 4),
            const Text(
              'Image unavailable',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class Section {
  final String id;
  final String name;

  const Section({required this.id, required this.name});

  factory Section.fromMap(Map<String, dynamic> map, {required String id}) {
    return Section(
      id: id,
      name: map['name'] ?? '',
    );
  }
}

class FoodData {
  // ── Shared stream caching (Phase 13) ──────────────────────────────────────
  //
  // Before Phase 13, `foodItemsStream` and `sectionsStream` created a NEW
  // Firestore snapshot listener on every access.  With Home, Categories and
  // CommonFood all subscribing independently, the full `food_items` and
  // `section` collections were downloaded multiple times per screen session.
  //
  // We now keep a single broadcast controller per collection, backed by one
  // Firestore listener that is created lazily on first subscription and
  // reused for the whole app lifetime.  All consumers share the same stream,
  // eliminating duplicate queries and reducing Firestore reads.
  //
  // A broadcast stream does not replay the last value to late subscribers,
  // so [foodItemsStream]/[_replayLive] first delivers the cached list to each
  // new listener (cache-first rendering) and then forwards live updates.

  static StreamController<List<FoodItem>>? _foodController;
  static StreamController<List<Section>>? _sectionController;
  static List<Section>? _cachedSections;

  /// Active Firestore snapshot subscriptions — kept so a failed listener can
  /// be cancelled and the stream recreated on the next access.  A Firestore
  /// snapshot listener stops after it emits an error and never resumes, so
  /// without this we could never recover from a single failure.
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _foodSub;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sectionSub;

  /// Last error emitted by the shared food stream — re-delivered to late
  /// subscribers so they see an error state instead of waiting forever.
  static Object? _foodError;
  static Object? _sectionError;

  /// Last emitted food list — used for instant cache-first rendering.
  static List<FoodItem>? cachedFoodItems;

  /// Stream of all food items from Firestore database to sync app state in real-time.
  ///
  /// Single shared broadcast stream: only one Firestore listener exists for
  /// the whole app, regardless of how many widgets subscribe.  New listeners
  /// first receive the cached list (if any), then live updates.
  static Stream<List<FoodItem>> get foodItemsStream {
    _ensureFoodStream();
    return _replayLive(cachedFoodItems, _foodError, _foodController!.stream);
  }

  /// Stream of all sections from the `section` collection (shared broadcast).
  static Stream<List<Section>> get sectionsStream {
    _ensureSectionStream();
    return _replayLive(
      _cachedSections,
      _sectionError,
      _sectionController!.stream,
    );
  }

  /// Lazily create the single `food_items` Firestore listener.
  static void _ensureFoodStream() {
    if (_foodController != null) return;
    final controller = StreamController<List<FoodItem>>.broadcast();
    _foodController = controller;
    // The subscription is stored so a failed listener can be torn down and
    // recreated on the next access.  A Firestore snapshot listener stops
    // after an error and never resumes, so the controller is reset on error.
    _foodSub = FirebaseFirestore.instance
        .collection('food_items')
        .snapshots()
        .listen((snapshot) {
          cachedFoodItems = snapshot.docs
              .map((doc) => FoodItem.fromMap(doc.data(), id: doc.id))
              .toList();
          _foodError = null;
          if (!controller.isClosed) {
            controller.add(cachedFoodItems!);
          }
        }, onError: (Object e) {
          _foodError = e;
          if (!controller.isClosed) controller.addError(e);
          _resetFoodStream();
        });
  }

  /// Lazily create the single `section` Firestore listener.
  static void _ensureSectionStream() {
    if (_sectionController != null) return;
    final controller = StreamController<List<Section>>.broadcast();
    _sectionController = controller;
    _sectionSub = FirebaseFirestore.instance
        .collection('section')
        .snapshots()
        .listen((snapshot) {
          _cachedSections = snapshot.docs
              .map((doc) => Section.fromMap(doc.data(), id: doc.id))
              .toList();
          _sectionError = null;
          if (!controller.isClosed) {
            controller.add(_cachedSections!);
          }
        }, onError: (Object e) {
          _sectionError = e;
          if (!controller.isClosed) controller.addError(e);
          _resetSectionStream();
        });
  }

  /// Tears down the shared `food_items` listener so the next subscription
  /// recreates it.  Cached items are kept for cache-first rendering, and
  /// [_foodError] is preserved so a late subscriber can still see the last
  /// error (only [resetStreams] clears it explicitly).
  static void _resetFoodStream() {
    _foodSub?.cancel();
    _foodSub = null;
    _foodController?.close();
    _foodController = null;
  }

  /// Tears down the shared `section` listener so the next subscription
  /// recreates it.  Cached sections are kept for cache-first rendering, and
  /// [_sectionError] is preserved so a late subscriber can still see the last
  /// error (only [resetStreams] clears it explicitly).
  static void _resetSectionStream() {
    _sectionSub?.cancel();
    _sectionSub = null;
    _sectionController?.close();
    _sectionController = null;
  }

  /// Resets both shared stream helpers (cancels the Firestore listeners and
  /// clears cached data/errors).  Call during sign-out and test teardown so
  /// the next access recreates fresh listeners with a clean slate.
  static void resetStreams() {
    _resetFoodStream();
    _resetSectionStream();
    _foodError = null;
    _sectionError = null;
    cachedFoodItems = null;
    _cachedSections = null;
  }

  /// Returns a stream that first emits [cached] (when non-null) and then
  /// forwards events from [live].  Gives cache-first rendering while keeping
  /// a single underlying Firestore listener.  If only an error is cached
  /// (no data ever arrived), the error is re-delivered so late subscribers
  /// see the error state instead of waiting indefinitely.
  static Stream<T> _replayLive<T>(T? cached, Object? error, Stream<T> live) {
    if (cached == null && error == null) return live;
    return Stream<T>.multi((controller) {
      if (cached != null) controller.add(cached);
      final sub = live.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
      if (cached == null && error != null) {
        controller.addError(error);
      }
    });
  }
}
