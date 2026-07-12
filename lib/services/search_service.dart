import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/food_data.dart';

class SearchService {
  // Cache to store previous search results in memory
  static final Map<String, List<FoodItem>> _cache = {};

  /// Searches for available food items in Firestore where `searchPrefixes` contains the query.
  /// Requirements:
  /// - Trim whitespace.
  /// - Convert query to lowercase.
  /// - Return empty list for empty query.
  /// - Query Firestore using searchPrefixes.
  /// - Only return available food items.
  /// - Cache previous results in memory.
  static Future<List<FoodItem>> searchFoods(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) {
      return [];
    }

    // Check memory cache first to avoid duplicate Firestore requests
    if (_cache.containsKey(cleanQuery)) {
      return _cache[cleanQuery]!;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('food_items')
          .where('available', isEqualTo: true)
          .where('searchPrefixes', arrayContains: cleanQuery)
          .get();

      final results = snapshot.docs.map((doc) {
        return FoodItem.fromMap(doc.data(), id: doc.id);
      }).toList();

      // Store in memory cache
      _cache[cleanQuery] = results;

      return results;
    } catch (e) {
      // Propagation of Firestore exception is handled by UI screen
      rethrow;
    }
  }

  /// Clears the search cache if needed (e.g. when menu gets updated or refreshed)
  static void clearCache() {
    _cache.clear();
  }
}
