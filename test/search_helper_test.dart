import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/services/search_helper.dart';

void main() {
  group('SearchHelper Tests', () {
    test('generateTitleLower converts to lowercase and trims', () {
      expect(SearchHelper.generateTitleLower('  Chicken Burger  '), 'chicken burger');
      expect(SearchHelper.generateTitleLower('PIZZA'), 'pizza');
    });

    test('generateKeywords extracts unique, lowercase words from title, category, and tags', () {
      final keywords = SearchHelper.generateKeywords(
        title: 'Chicken Burger',
        category: 'Burgers',
        tags: ['Fast Food', 'Lunch'],
      );

      // Verify lowercase conversion and duplicates removal
      expect(keywords, containsAll([
        'chicken',
        'burger',
        'burgers',
        'fast',
        'food',
        'lunch'
      ]));

      // Verify no duplicates
      final uniqueCount = keywords.toSet().length;
      expect(keywords.length, uniqueCount);
    });

    test('generateSearchPrefixes generates unique, lowercase prefixes for title, category, and tags', () {
      final prefixes = SearchHelper.generateSearchPrefixes(
        title: 'Bite',
        category: 'Lunch',
        tags: ['Hot'],
      );

      // Prefixes for 'Bite' (full: "bite", words: "b", "bi", "bit", "bite")
      expect(prefixes, containsAll(['b', 'bi', 'bit', 'bite']));

      // Prefixes for 'Lunch' (full: "lunch", words: "l", "lu", "lun", "lunc", "lunch")
      expect(prefixes, containsAll(['l', 'lu', 'lun', 'lunc', 'lunch']));

      // Prefixes for 'Hot' (full: "hot", words: "h", "ho", "hot")
      expect(prefixes, containsAll(['h', 'ho', 'hot']));

      // Verify no duplicates
      final uniqueCount = prefixes.toSet().length;
      expect(prefixes.length, uniqueCount);
    });

    test('generateSearchPrefixes generates prefixes for multi-word titles', () {
      final prefixes = SearchHelper.generateSearchPrefixes(
        title: 'Hot Pizza',
        category: 'Teasers',
        tags: [],
      );

      // Should have prefixes for the whole string 'hot pizza'
      expect(prefixes, containsAll([
        'h', 'ho', 'hot',
        'hot ', 'hot p', 'hot pi', 'hot piz', 'hot pizz', 'hot pizza'
      ]));

      // Should also have prefixes for the individual word 'pizza'
      expect(prefixes, containsAll([
        'p', 'pi', 'piz', 'pizz', 'pizza'
      ]));
    });
  });
}
