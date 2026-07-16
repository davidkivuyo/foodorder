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
import 'package:campusbite/widgets/special_banner_card.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [child] in a bounded MaterialApp + Scaffold.
/// The SizedBox provides finite constraints so the PageView can lay out.
Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 600,
        child: child,
      ),
    ),
  );
}

/// Returns the `width` property of every [AnimatedContainer] that is a
/// descendant of a [Row].  These are the pagination dot indicators.
///
/// We read the *widget* property (not the rendered RenderBox size) because
/// the RenderBox includes the margin specified separately on the container.
List<double> _dotWidgetWidths(WidgetTester tester) {
  return tester
      .widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(Row),
          matching: find.byType(AnimatedContainer),
        ),
      )
      .map((c) => c.constraints!.maxWidth)
      .toList();
}

// ---------------------------------------------------------------------------
// Suite-level image-error suppression.
//
// Flutter's test binding treats any exception reported through
// FlutterError.onError as a test failure, including the
// NetworkImageLoadException that Image.network emits when it can't reach the
// server (status 400 in tests).  We install a custom handler in setUp/tearDown
// to swallow those specific exceptions so that the tests focus on widget logic.
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
  setUp(_installImageErrorSuppressor);
  tearDown(_removeImageErrorSuppressor);

  // -------------------------------------------------------------------------
  // 1. Empty image list
  // -------------------------------------------------------------------------
  group('SpecialBannerCard — empty imageUrls', () {
    testWidgets('renders nothing (SizedBox.shrink) when imageUrls is empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const SpecialBannerCard(imageUrls: [])));
      await tester.pump();

      // Widget returns SizedBox.shrink() → no PageView should be present.
      expect(find.byType(PageView), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 2. Single image
  // -------------------------------------------------------------------------
  group('SpecialBannerCard — single image', () {
    const singleUrl = ['https://example.com/banner1.jpg'];

    testWidgets('renders a PageView', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(SpecialBannerCard(imageUrls: singleUrl)));
      // pump() — no settle because the image 400 triggers the error handler.
      await tester.pump();

      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('does NOT render dot indicators for a single image',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(SpecialBannerCard(imageUrls: singleUrl)));
      await tester.pump();

      // The dot row is hidden by `if (widget.imageUrls.length > 1)`.
      final dotFinder = find.descendant(
        of: find.byType(Row),
        matching: find.byType(AnimatedContainer),
      );
      expect(dotFinder, findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 3. Multiple images
  // -------------------------------------------------------------------------
  group('SpecialBannerCard — multiple images', () {
    const urls = [
      'https://example.com/banner1.jpg',
      'https://example.com/banner2.jpg',
      'https://example.com/banner3.jpg',
    ];

    testWidgets('renders a PageView', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(SpecialBannerCard(imageUrls: urls)));
      await tester.pump();

      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('renders the correct number of dot indicators',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(SpecialBannerCard(imageUrls: urls)));
      await tester.pump();

      final dotFinder = find.descendant(
        of: find.byType(Row),
        matching: find.byType(AnimatedContainer),
      );
      expect(dotFinder, findsNWidgets(urls.length));
    });

    testWidgets('first dot is active (width 24) on initial render',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(SpecialBannerCard(imageUrls: urls)));
      await tester.pump();

      final widths = _dotWidgetWidths(tester);
      expect(widths.length, urls.length);
      expect(widths[0], 24.0); // active dot width
      expect(widths[1], 8.0);
      expect(widths[2], 8.0);
    });
  });

  // -------------------------------------------------------------------------
  // 4. onTap callback
  // -------------------------------------------------------------------------
  group('SpecialBannerCard — onTap callback', () {
    const urls = [
      'https://example.com/banner1.jpg',
      'https://example.com/banner2.jpg',
    ];

    testWidgets('calls onTap with index 0 when first banner is tapped',
        (WidgetTester tester) async {
      int? tappedIndex;

      await tester.pumpWidget(
        _wrap(
          SpecialBannerCard(
            imageUrls: urls,
            onTap: (index) => tappedIndex = index,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();

      expect(tappedIndex, 0);
    });

    testWidgets('does not throw when onTap is null and banner is tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(SpecialBannerCard(imageUrls: urls)));
      await tester.pump();

      // Should complete without exception.
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
    });
  });

  // -------------------------------------------------------------------------
  // 5. Auto-scroll timer
  // -------------------------------------------------------------------------
  group('SpecialBannerCard — auto-scroll timer', () {
    const urls = [
      'https://example.com/banner1.jpg',
      'https://example.com/banner2.jpg',
      'https://example.com/banner3.jpg',
    ];

    testWidgets('active dot advances to index 1 after 4-second tick',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(SpecialBannerCard(imageUrls: urls)));
      await tester.pump();

      // Page 0 is initially active.
      expect(_dotWidgetWidths(tester)[0], 24.0);
      expect(_dotWidgetWidths(tester)[1], 8.0);

      // Advance fake time by 4 s (timer tick) + settle the 200 ms animation.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));

      final widths = _dotWidgetWidths(tester);
      expect(widths[0], 8.0);
      expect(widths[1], 24.0);
    });

    testWidgets('wraps back to page 0 after last page',
        (WidgetTester tester) async {
      const twoUrls = [
        'https://example.com/banner1.jpg',
        'https://example.com/banner2.jpg',
      ];

      await tester.pumpWidget(_wrap(SpecialBannerCard(imageUrls: twoUrls)));
      await tester.pump();

      // Tick 1 → page 1
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_dotWidgetWidths(tester)[1], 24.0);

      // Tick 2 → wraps back to page 0
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));

      expect(_dotWidgetWidths(tester)[0], 24.0);
      expect(_dotWidgetWidths(tester)[1], 8.0);
    });
  });

  // -------------------------------------------------------------------------
  // 6. Custom dimensions
  // -------------------------------------------------------------------------
  group('SpecialBannerCard — custom dimensions', () {
    const urls = ['https://example.com/banner1.jpg'];

    testWidgets('respects custom height', (WidgetTester tester) async {
      const customHeight = 220.0;

      await tester.pumpWidget(
        _wrap(SpecialBannerCard(imageUrls: urls, height: customHeight)),
      );
      await tester.pump();

      // The widget builds a SizedBox with the given height.
      final match = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((b) => b.height == customHeight);
      expect(match, isNotEmpty,
          reason: 'Expected a SizedBox with height $customHeight');
    });

    testWidgets('respects custom borderRadius', (WidgetTester tester) async {
      const customRadius = 24.0;

      await tester.pumpWidget(
        _wrap(SpecialBannerCard(imageUrls: urls, borderRadius: customRadius)),
      );
      await tester.pump();

      final clipRRect = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(clipRRect.borderRadius, BorderRadius.circular(customRadius));
    });
  });

  // -------------------------------------------------------------------------
  // 7. Manual swipe
  // -------------------------------------------------------------------------
  group('SpecialBannerCard — manual swipe', () {
    const urls = [
      'https://example.com/banner1.jpg',
      'https://example.com/banner2.jpg',
    ];

    testWidgets('swiping left updates active dot to index 1',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(SpecialBannerCard(imageUrls: urls)));
      await tester.pump();

      // Page 0 is active.
      expect(_dotWidgetWidths(tester)[0], 24.0);

      // Drag the Scrollable inside the PageView to the left.
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(-400, 0),
      );
      // Pump the swipe animation (350 ms) + dot animation (200 ms).
      await tester.pump(const Duration(milliseconds: 600));

      expect(_dotWidgetWidths(tester)[1], 24.0);
      expect(_dotWidgetWidths(tester)[0], 8.0);
    });
  });

  // -------------------------------------------------------------------------
  // 8. Disposal
  // -------------------------------------------------------------------------
  group('SpecialBannerCard — disposal', () {
    testWidgets('disposes without error when removed from tree',
        (WidgetTester tester) async {
      const urls = ['https://example.com/a.jpg', 'https://example.com/b.jpg'];

      await tester.pumpWidget(_wrap(SpecialBannerCard(imageUrls: urls)));
      await tester.pump();

      // Replace tree — triggers dispose().
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pump();
      // Passing without exception confirms dispose() is correct.
    });
  });
}
