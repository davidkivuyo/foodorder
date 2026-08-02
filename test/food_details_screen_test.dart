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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/screens/food_details.dart';
import 'package:campusbite/data/food_data.dart';
import 'firebase_test_helper.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [child] in a MaterialApp so navigator and theme context are available.
Widget _wrap(Widget child) {
  return MaterialApp(
    home: child,
  );
}

/// Builds a minimal [FoodItem] with the given overrides.
///
/// Returns a fully configured item so each test can override only the
/// fields it cares about.
FoodItem _foodItem({
  String title = 'The Varsity Burger',
  String subtitle = 'Double grass-fed beef',
  String description = 'A delicious campus burger.',
  int price = 12990,
  double rating = 4.4,
  bool available = true,
  bool featured = false,
  String category = '',
  List<String>? availableCafes,
  List<String>? dietaryTags,
  String time = '20-30 min',
  String image = 'https://example.com/burger.jpg',
}) {
  return FoodItem(
    id: 'test_item_1',
    image: image,
    title: title,
    titleLower: title.toLowerCase(),
    subtitle: subtitle,
    description: description,
    price: price,
    rating: rating,
    // FoodDetailsScreen displays averageRating (Phase 12) — mirror the
    // helper's rating override so rating text assertions match the UI.
    averageRating: rating,
    category: category,
    availableCafes: availableCafes ?? ['Main Cafeteria'],
    time: time,
    section: 'test',
    available: available,
    featured: featured,
    dietaryTags: dietaryTags ?? [],
  );
}

// ---------------------------------------------------------------------------
// Suite-level image-error suppression.
//
// FoodItem.buildImage uses CachedNetworkImage which triggers network errors
// in the test environment. We suppress those errors following the same
// pattern used in special_banner_card_test.dart.
// ---------------------------------------------------------------------------
FlutterExceptionHandler? _originalOnError;

void _installImageErrorSuppressor() {
  _originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exception.toString();
    if (msg.contains('NetworkImageLoadException') ||
        msg.contains('HTTP request failed')) {
      // Silently swallow image load failures caused by the test environment
      // returning HTTP 400 for every network request.
      return;
    }
    _originalOnError?.call(details);
  };
}

void _removeImageErrorSuppressor() {
  FlutterError.onError = _originalOnError;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // FoodDetailsScreen constructs a ReviewService (and thus accesses
  // FirebaseFirestore.instance) during initState, so Firebase must be
  // initialized before any test pumps the widget.
  setUpAll(() async {
    await setupFirebaseForTest();
  });

  setUp(_installImageErrorSuppressor);
  tearDown(_removeImageErrorSuppressor);

  // ────────────────────────────────────────────────────────────────────────
  // 1. Basic data rendering
  // ────────────────────────────────────────────────────────────────────────
  group('FoodDetailsScreen — data rendering', () {
    testWidgets('renders title, price, rating, and subtitle',
        (WidgetTester tester) async {
      final item = _foodItem(
        title: 'Pepperoni Pizza',
        subtitle: 'Classic pepperoni with mozzarella',
        description: 'A timeless favourite.',
        price: 15000,
        rating: 4.7,
        category: 'Lunch',
        availableCafes: ['Cafe A', 'Cafe B'],
        time: '15-20 min',
      );

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      // pump() — do not pumpAndSettle because image loads trigger errors.
      await tester.pump();

      // Title and subtitle
      expect(find.text('Pepperoni Pizza'), findsOneWidget);
      expect(
        find.text('Classic pepperoni with mozzarella'),
        findsOneWidget,
      );

      // Price (TZS format)
      expect(find.text('TZS 15000'), findsOneWidget);

      // Rating
      expect(find.text('4.7'), findsOneWidget);

      // Time
      expect(find.textContaining('15-20 min'), findsOneWidget);

      // Category section
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
    });

    testWidgets('renders description when provided',
        (WidgetTester tester) async {
      final item = _foodItem(
        title: 'Pasta Carbonara',
        subtitle: 'Creamy and rich',
        description: 'Made with fresh eggs, parmesan, and pancetta.',
        price: 11000,
        rating: 4.5,
        availableCafes: ['Cafe A'],
      );

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      expect(find.text('Description'), findsOneWidget);
      expect(
        find.text('Made with fresh eggs, parmesan, and pancetta.'),
        findsOneWidget,
      );
    });

    testWidgets('hides description section when description is empty',
        (WidgetTester tester) async {
      final item = _foodItem(description: '');

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      expect(find.text('Description'), findsNothing);
    });

    testWidgets('renders without subtitle when subtitle is empty',
        (WidgetTester tester) async {
      final item = _foodItem(subtitle: '');

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      // Ensure basic data still renders
      expect(find.text('The Varsity Burger'), findsOneWidget);
      expect(find.text('TZS 12990'), findsOneWidget);
      // Empty subtitle should not produce a visible text widget
      // (no assertion needed — the test just verifies no error)
    });

    testWidgets('renders without time suffix when time is empty',
        (WidgetTester tester) async {
      final item = _foodItem(time: '');

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      // Basic data still renders
      expect(find.text('The Varsity Burger'), findsOneWidget);
      expect(find.text('TZS 12990'), findsOneWidget);
      // The default time '20-30 min' should NOT appear since we passed ''
      expect(find.textContaining('20-30 min'), findsNothing);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 2. Bestseller badge
  // ────────────────────────────────────────────────────────────────────────
  group('FoodDetailsScreen — Bestseller badge', () {
    testWidgets('shows Bestseller badge when featured is true',
        (WidgetTester tester) async {
      final item = _foodItem(featured: true);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      expect(find.text('Bestseller'), findsOneWidget);
    });

    testWidgets('hides Bestseller badge when featured is false',
        (WidgetTester tester) async {
      final item = _foodItem(featured: false);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      expect(find.text('Bestseller'), findsNothing);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 3. Stock / availability
  // ────────────────────────────────────────────────────────────────────────
  group('FoodDetailsScreen — stock status', () {
    testWidgets('shows Out of Stock badges when item is unavailable',
        (WidgetTester tester) async {
      final item = _foodItem(available: false);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      // Both StockOverlayBadge (image overlay) and StockBadge (inline)
      // render "Out of Stock" text — at least one should be visible.
      expect(find.textContaining('Out of Stock'), findsAtLeastNWidgets(1));
    });

    testWidgets('hides Out of Stock badge when item is available',
        (WidgetTester tester) async {
      final item = _foodItem(available: true);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      expect(find.textContaining('Out of Stock'), findsNothing);
    });

    testWidgets(
        'disables Add to Cart button and shows Unavailable when out of stock',
        (WidgetTester tester) async {
      final item = _foodItem(available: false);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      // The button label should say "Unavailable"
      expect(find.text('Unavailable'), findsOneWidget);

      // The "Add to Cart • TZS ..." text should NOT appear
      expect(find.textContaining('Add to Cart'), findsNothing);
    });

    testWidgets(
        'enables Add to Cart button and shows price when in stock',
        (WidgetTester tester) async {
      final item = _foodItem(price: 12990);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      // Button shows "Add to Cart • TZS 12990" (1 item)
      expect(find.text('Add to Cart • TZS 12990'), findsOneWidget);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 4. Quantity selector
  // ────────────────────────────────────────────────────────────────────────
  group('FoodDetailsScreen — quantity selector', () {
    testWidgets('starts with quantity 1', (WidgetTester tester) async {
      final item = _foodItem(price: 10000);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      // Quantity text shows "1"
      expect(find.text('1'), findsOneWidget);

      // Button shows price for quantity 1
      expect(find.text('Add to Cart • TZS 10000'), findsOneWidget);
    });

    testWidgets('increments quantity when + is tapped',
        (WidgetTester tester) async {
      final item = _foodItem(price: 10000);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      // Tap the add (+) button
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      // Quantity should now show "2"
      expect(find.text('2'), findsOneWidget);

      // Price should update to TZS 20000
      expect(find.text('Add to Cart • TZS 20000'), findsOneWidget);
    });

    testWidgets('decrements quantity when - is tapped',
        (WidgetTester tester) async {
      final item = _foodItem(price: 10000);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      // First increment to 2 so we can decrement back to 1
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      // Now tap the remove (-) button
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();

      // Quantity should be back to 1
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Add to Cart • TZS 10000'), findsOneWidget);
    });

    testWidgets('does not decrement below 1', (WidgetTester tester) async {
      final item = _foodItem(price: 10000);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      // Tap remove when quantity is 1 — should stay at 1
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('Add to Cart • TZS 10000'), findsOneWidget);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 5. Available Cafes
  // ────────────────────────────────────────────────────────────────────────
  group('FoodDetailsScreen — available cafes', () {
    testWidgets('shows available cafes section', (WidgetTester tester) async {
      final item = _foodItem(availableCafes: ['Main Cafeteria', 'East Wing']);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      expect(find.text('Available At'), findsOneWidget);
      expect(find.text('Main Cafeteria'), findsOneWidget);
      expect(find.text('East Wing'), findsOneWidget);
    });

    testWidgets('hides available cafes section when list is empty',
        (WidgetTester tester) async {
      final item = _foodItem(availableCafes: []);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      expect(find.text('Available At'), findsNothing);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 6. Dietary Tags
  // ────────────────────────────────────────────────────────────────────────
  group('FoodDetailsScreen — dietary tags', () {
    testWidgets('shows dietary tags when provided', (WidgetTester tester) async {
      final item = _foodItem(dietaryTags: ['Vegetarian', 'Spicy', 'Gluten-Free']);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      expect(find.text('Dietary Info'), findsOneWidget);
      expect(find.text('Vegetarian'), findsOneWidget);
      expect(find.text('Spicy'), findsOneWidget);
      expect(find.text('Gluten-Free'), findsOneWidget);
    });

    testWidgets('hides dietary tags section when list is empty',
        (WidgetTester tester) async {
      final item = _foodItem(dietaryTags: []);

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      expect(find.text('Dietary Info'), findsNothing);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 7. Category section
  // ────────────────────────────────────────────────────────────────────────
  group('FoodDetailsScreen — category', () {
    testWidgets('shows category when provided', (WidgetTester tester) async {
      final item = _foodItem(category: 'Drinks');

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Drinks'), findsOneWidget);
    });

    testWidgets('hides category section when category is empty',
        (WidgetTester tester) async {
      final item = _foodItem(category: '');

      await tester.pumpWidget(_wrap(FoodDetailsScreen(item: item)));
      await tester.pump();

      expect(find.text('Category'), findsNothing);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 8. Hero tag
  // ────────────────────────────────────────────────────────────────────────
  group('FoodDetailsScreen — hero tag', () {
    testWidgets('uses the correct hero tag format for image transition',
        (WidgetTester tester) async {
      final item = _foodItem(
        title: 'Burger',
        image: 'burger.jpg',
        price: 5000,
        rating: 4.0,
        availableCafes: ['Cafe X'],
        description: 'Tasty',
      );

      await tester.pumpWidget(
        _wrap(FoodDetailsScreen(item: item, heroTagPrefix: 'home_')),
      );
      await tester.pump();

      // Verify the Hero widget exists with the correct tag pattern
      final heroWidget = tester.widget<Hero>(find.byType(Hero));
      expect(
        heroWidget.tag,
        'home_Cafe X_Burger_burger.jpg',
      );
    });

    testWidgets('uses custom heroTagPrefix when provided',
        (WidgetTester tester) async {
      final item = _foodItem(
        title: 'Pizza',
        image: 'pizza.jpg',
        price: 8000,
        rating: 4.2,
        availableCafes: ['Cafe Y'],
        description: 'Delicious',
      );

      await tester.pumpWidget(
        _wrap(FoodDetailsScreen(item: item, heroTagPrefix: 'category_')),
      );
      await tester.pump();

      final heroWidget = tester.widget<Hero>(find.byType(Hero));
      expect(
        heroWidget.tag,
        'category_Cafe Y_Pizza_pizza.jpg',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 9. Back button
  // ────────────────────────────────────────────────────────────────────────
  group('FoodDetailsScreen — back button', () {
    testWidgets('back button pops to the previous route',
        (WidgetTester tester) async {
      final item = _foodItem();
      final navigatorKey = GlobalKey<NavigatorState>();

      // 1. Mount an app with an initial route.
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(
            body: Center(
              child: Text('Initial Route'),
            ),
          ),
        ),
      );
      expect(find.text('Initial Route'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isFalse,
          reason: 'Root route should have no route below');

      // 2. Push the FoodDetailsScreen onto the stack.
      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => FoodDetailsScreen(item: item),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Confirm we can now pop (two routes on the stack).
      expect(navigatorKey.currentState!.canPop(), isTrue);

      // 3. Tap the back arrow button.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 4. Verify we returned to the root (no route below).
      expect(navigatorKey.currentState!.canPop(), isFalse,
          reason: 'Popped back to root — no more routes to go back to');

      // 5. The initial route's content should be on stage again.
      expect(find.text('Initial Route'), findsOneWidget);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 10. Custom heroTagPrefix with multiple cafes
  // ────────────────────────────────────────────────────────────────────────
  group('FoodDetailsScreen — displayCafe handles multiple cafes', () {
    testWidgets('hero tag uses joined cafe names', (WidgetTester tester) async {
      final item = _foodItem(
        title: 'Salad',
        image: 'salad.jpg',
        price: 7000,
        rating: 4.8,
        availableCafes: ['Cafe A', 'Cafe B', 'Cafe C'],
        description: 'Healthy',
      );

      await tester.pumpWidget(
        _wrap(FoodDetailsScreen(item: item, heroTagPrefix: 'fav_')),
      );
      await tester.pump();

      final heroWidget = tester.widget<Hero>(find.byType(Hero));
      // displayCafe = Cafe A, Cafe B, Cafe C
      expect(
        heroWidget.tag,
        'fav_Cafe A, Cafe B, Cafe C_Salad_salad.jpg',
      );
    });
  });
}
