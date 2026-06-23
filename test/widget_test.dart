import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/main.dart';
import 'package:campusbite/screens/order_screen.dart';
import 'package:campusbite/screens/account_screen.dart';

void main() {
  testWidgets('App skeleton and navigation test', (WidgetTester tester) async {
    // 1. Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // 2. Verify that AppBar title 'CampusBite' exists
    expect(find.text('CampusBite'), findsOneWidget);

    // 3. Verify that the bottom navigation bar has the correct destinations
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);

    // 4. Verify initial screen is HomeScreen (should contain "Welcome DAVID!" and "Today's Menu: CAFE 1")
    expect(find.text('Welcome DAVID!'), findsOneWidget);
    expect(find.text("Today's Menu: CAFE 1"), findsOneWidget);

    // 5. Navigate to Categories screen
    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();

    // Verify Categories screen content is shown
    expect(find.text('Explore Categories'), findsOneWidget);
    expect(find.text('Breakfast'), findsOneWidget);

    // 6. Navigate to Orders screen
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();

    // Verify Orders screen placeholder content is shown
    expect(find.byType(OrdersScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(OrdersScreen), matching: find.text('Orders')), findsOneWidget);

    // 7. Navigate to Account screen
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    // Verify Account screen placeholder content is shown
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(AccountScreen), matching: find.text('Account')), findsOneWidget);
  });
}
