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

class SearchHelper {
  /// Converts everything in a string to lowercase.
  static String generateTitleLower(String title) {
    return title.trim().toLowerCase();
  }

  /// Automatically generates keywords for a food item.
  /// Requirements:
  /// - Convert everything to lowercase.
  /// - Remove duplicate values.
  /// - Generate keywords for every word in the title.
  /// - Generate keywords for category and tags as well.
  static List<String> generateKeywords({
    required String title,
    required String category,
    required List<String> tags,
  }) {
    final keywords = <String>{};

    // Words in title
    final titleWords = title.trim().toLowerCase().split(RegExp(r'\s+'));
    for (final word in titleWords) {
      if (word.isNotEmpty) {
        keywords.add(word);
      }
    }

    // Category
    final catClean = category.trim().toLowerCase();
    if (catClean.isNotEmpty) {
      keywords.add(catClean);
      final catWords = catClean.split(RegExp(r'\s+'));
      for (final word in catWords) {
        if (word.isNotEmpty) {
          keywords.add(word);
        }
      }
    }

    // Tags
    for (final tag in tags) {
      final tagClean = tag.trim().toLowerCase();
      if (tagClean.isNotEmpty) {
        keywords.add(tagClean);
        final tagWords = tagClean.split(RegExp(r'\s+'));
        for (final word in tagWords) {
          if (word.isNotEmpty) {
            keywords.add(word);
          }
        }
      }
    }

    return keywords.toList();
  }

  /// Automatically generates search prefixes (partial strings) for a food item.
  /// Requirements:
  /// - Convert everything to lowercase.
  /// - Remove duplicate values.
  /// - Generate prefixes for every word in the title.
  /// - Generate prefixes for category and tags as well.
  static List<String> generateSearchPrefixes({
    required String title,
    required String category,
    required List<String> tags,
  }) {
    final prefixes = <String>{};

    void addPrefixesForText(String text) {
      final cleanText = text.trim().toLowerCase();
      if (cleanText.isEmpty) return;

      // Full prefix generator (e.g. "chicken burger" -> "c", "ch", ..., "chicken burger")
      for (int i = 1; i <= cleanText.length; i++) {
        prefixes.add(cleanText.substring(0, i));
      }

      // Generate prefixes for individual words (like title words)
      final words = cleanText.split(RegExp(r'\s+'));
      for (final word in words) {
        if (word.isEmpty) continue;
        for (int i = 1; i <= word.length; i++) {
          prefixes.add(word.substring(0, i));
        }
      }
    }

    // Generate prefixes for title
    addPrefixesForText(title);

    // Generate prefixes for category
    addPrefixesForText(category);

    // Generate prefixes for tags
    for (final tag in tags) {
      addPrefixesForText(tag);
    }

    return prefixes.toList();
  }
}
