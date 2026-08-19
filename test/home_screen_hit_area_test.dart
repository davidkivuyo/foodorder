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

import 'package:campusbite/data/food_data.dart';
import 'package:campusbite/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the two [IconButton] controls in [CardRowItems] (the section
/// action arrow and the quick-add button) expose a 48×48 logical-pixel
/// minimum hit area while keeping a compact visual footprint.
///
/// The effective hit area is measured on the button's OUTER box — the same
/// bounds the accessibility inspector reports for the button's semantics
/// node. Material 3 expands that outer box to at least 48×48 when the tap
/// target size is `padded` (the default) without growing the visible icon.
void main() {
  Widget harness({required Widget child}) {
    return MaterialApp(home: Scaffold(body: child));
  }

  testWidgets('section action arrow exposes a 48×48 hit area with a compact '
      'icon', (WidgetTester tester) async {
    await tester.pumpWidget(harness(
      child: const CardRowItems(title: 'Test section', items: []),
    ));
    await tester.pump();

    final arrowButton = find.ancestor(
      of: find.byIcon(Icons.arrow_forward),
      matching: find.byType(IconButton),
    );
    expect(arrowButton, findsOneWidget);

    // Effective tap target (semantics/outer box) — accessibility inspector
    // equivalent.
    final hitArea = tester.getSize(arrowButton);
    expect(hitArea.width, greaterThanOrEqualTo(48));
    expect(hitArea.height, greaterThanOrEqualTo(48));

    // The visible icon stays compact — the padded target must not grow it.
    final iconSize = tester.getSize(find.byIcon(Icons.arrow_forward));
    expect(iconSize.width, lessThan(48));
    expect(iconSize.height, lessThan(48));
  });

  testWidgets('quick-add control exposes a 48×48 hit area with a compact '
      'icon', (WidgetTester tester) async {
    final item = FoodItem(
      id: 'f1',
      title: 'Test meal',
      titleLower: 'test meal',
      // Empty (non-network) image so the card renders its error placeholder
      // instead of attempting HTTP in the test.
      image: '',
      availableCafes: const ['Cafe A'],
      time: '10 min',
    );
    await tester.pumpWidget(harness(
      child: CardRowItems(title: 'Test section', items: [item]),
    ));
    await tester.pump();

    final addButton = find.ancestor(
      of: find.byIcon(Icons.add_rounded),
      matching: find.byType(IconButton),
    );
    expect(addButton, findsOneWidget);

    final hitArea = tester.getSize(addButton);
    expect(hitArea.width, greaterThanOrEqualTo(48));
    expect(hitArea.height, greaterThanOrEqualTo(48));

    final iconSize = tester.getSize(find.byIcon(Icons.add_rounded));
    expect(iconSize.width, lessThan(48));
    expect(iconSize.height, lessThan(48));
  });
}
