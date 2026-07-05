import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FoodItem {
  final String image;
  final String title;
  final String subtitle;
  final int price;
  final double rating;
  final String category;
  final String cafe;
  final String time;
  final String section;

  const FoodItem({
    required this.image,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.rating,
    required this.category,
    required this.cafe,
    required this.time,
    this.section = '',
  });

  factory FoodItem.fromMap(Map<String, dynamic> map) {
    return FoodItem(
      image: map['image'] ?? '',
      title: map['title'] ?? '',
      subtitle: map['subtitle'] ?? '',
      price: map['price'] is int
          ? map['price']
          : int.tryParse(map['price']?.toString() ?? '') ?? 0,
      rating: (map['rating'] ?? 4.5).toDouble(),
      category: map['category'] ?? '',
      cafe: map['cafe'] ?? 'all',
      time: map['time'] ?? '',
      section: map['section'] ?? '',
    );
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

class FoodData {
  /// Stream of all food items from Firestore database to sync app state in real-time
  static Stream<List<FoodItem>> get foodItemsStream {
    return FirebaseFirestore.instance.collection('food_items').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) {
        return FoodItem.fromMap(doc.data());
      }).toList();
    });
  }
}
