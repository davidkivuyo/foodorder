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

import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/main.dart';
import 'package:campusbite/screens/order_screen.dart';
import 'package:campusbite/screens/account_screen.dart';

void main() {
  testWidgets('App skeleton and navigation test', (WidgetTester tester) async {
    // 1. Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // 2. Verify that AppBar title 'Campus Bite' exists
    expect(find.text('Campus Bite'), findsOneWidget);

    // 3. Verify that the bottom navigation bar has the correct destinations
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);

    // 4. Verify initial screen is HomeScreen (should contain "Search your next meal" and "Favourite on campus")
    expect(find.text('Search your next meal'), findsOneWidget);
    expect(find.text('Favourite on campus'), findsOneWidget);

    // 5. Navigate to Categories screen
    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();

    // Verify Categories screen content is shown
    expect(find.text('Explore Categories'), findsOneWidget);
    expect(find.textContaining('Breakfast'), findsOneWidget);

    // 6. Navigate to Orders screen
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();

    // Verify Orders screen placeholder content is shown
    expect(find.byType(OrdersScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(OrdersScreen), matching: find.textContaining('orders')), findsOneWidget);

    // 7. Navigate to Account screen
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    // Verify Account screen placeholder content is shown
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(AccountScreen), matching: find.textContaining('Account')), findsOneWidget);
  });
}
