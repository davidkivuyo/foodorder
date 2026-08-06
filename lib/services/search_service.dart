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

import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/food_data.dart';
import 'analytics_service.dart';
import 'performance_service.dart';

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

    // Phase 17 — anonymous search event (no query text is ever collected).
    AnalyticsService.instance.logEvent(AnalyticsEvent.foodSearched);

    // Check memory cache first to avoid duplicate Firestore requests
    if (_cache.containsKey(cleanQuery)) {
      return _cache[cleanQuery]!;
    }

    final trace = PerformanceService.instance.startTrace(kTraceSearch);
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
    } on Exception catch (_) {
      // Propagation of Firestore exception is handled by UI screen
      rethrow;
    } finally {
      trace?.stop();
    }
  }

  /// Clears the search cache if needed (e.g. when menu gets updated or refreshed)
  static void clearCache() {
    _cache.clear();
  }
}
