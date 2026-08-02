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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/data/food_data.dart';
import 'package:campusbite/main.dart';
import 'firebase_test_helper.dart';

void main() {
  setUpAll(() async {
    await setupFirebaseForTest();
  });

  tearDown(() {
    // Reset the shared Firestore menu/section streams so cached data and
    // listeners never leak between tests.
    FoodData.resetStreams();
  });

  testWidgets('App renders correctly with no signed-in user',
      (WidgetTester tester) async {
    // 1. Build the app and trigger a frame.
    // The router redirects unauthenticated users to '/' (WelcomeScreen).
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // 2. The WelcomeScreen is shown — verify its key elements.
    // The logo text is "CampusBite" (no space).
    expect(find.text('CampusBite'), findsOneWidget);
    expect(find.text('Campus Bite'), findsNothing);

    // 3. Welcome screen main CTA button.
    expect(find.text('Start Ordering'), findsOneWidget);

    // 4. Sign In link inside RichText.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('Sign In'),
      ),
      findsOneWidget,
    );
  });
}
