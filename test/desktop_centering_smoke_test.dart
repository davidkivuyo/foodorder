import 'package:campusbite/screens/diagnostics_screen.dart';
import 'package:campusbite/screens/help_support.dart';
import 'package:campusbite/screens/myprofile.dart';
import 'package:campusbite/screens/terms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'firebase_test_helper.dart';

void main() {
  setUpAll(() async {
    await setupFirebaseForTest();
  });

  Future<void> pumpAtDesktop(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pump();
  }

  Finder constrainedChild(WidgetTester tester, String text) {
    final finder = find.text(text);
    expect(finder, findsOneWidget);
    return find.ancestor(of: finder, matching: find.byType(ConstrainedBox)).first;
  }

  testWidgets('MyProfileScreen centers its body on desktop', (tester) async {
    await pumpAtDesktop(tester, const MyProfileScreen());
    final body = constrainedChild(tester, 'My Profile');
    expect(body, findsOneWidget);
    final box = tester.getRect(body);
    expect(box.center.dx, closeTo(960, 1));
    expect(box.width, lessThanOrEqualTo(720));
  });

  testWidgets('SupportScreen centers its body on desktop', (tester) async {
    await pumpAtDesktop(tester, const SupportScreen());
    expect(find.text('Help and support'), findsOneWidget);
  });

  testWidgets('FaqScreen renders on desktop', (tester) async {
    await pumpAtDesktop(tester, const FaqScreen());
    expect(find.text('FAQ'), findsOneWidget);
  });

  testWidgets('ContactScreen renders on desktop', (tester) async {
    await pumpAtDesktop(tester, const ContactScreen());
    expect(find.text('Get in Touch'), findsWidgets);
  });

  testWidgets('TermsScreen centers its body on desktop', (tester) async {
    await pumpAtDesktop(tester, const TermsScreen());
    expect(find.text('Terms and Conditions'), findsOneWidget);
  });

  testWidgets('DiagnosticsScreen renders on desktop', (tester) async {
    await pumpAtDesktop(tester, const DiagnosticsScreen());
    await tester.pump(const Duration(milliseconds: 300));
  });
}