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
  final bool available;
  final bool featured;
  final int quantity;
  final List<String> dietaryTags;
  final List<String> keywords;
  final List<String> searchPrefixes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FoodItem({
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
  /// Stream of all food items from Firestore database to sync app state in real-time
  static Stream<List<FoodItem>> get foodItemsStream {
    return FirebaseFirestore.instance.collection('food_items').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) {
        return FoodItem.fromMap(doc.data(), id: doc.id);
      }).toList();
    });
  }

  /// Stream of all sections from the `section` collection
  static Stream<List<Section>> get sectionsStream {
    return FirebaseFirestore.instance.collection('section').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) {
        return Section.fromMap(doc.data(), id: doc.id);
      }).toList();
    });
  }
}
