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

import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:campusbite/navigation/router.dart';
import 'package:campusbite/screens/diagnostics_screen.dart';
import 'package:campusbite/services/analytics_service.dart';
import 'package:campusbite/services/app_log.dart';
import 'package:campusbite/services/crash_reporting_service.dart';
import 'package:campusbite/services/error_service.dart';
import 'package:campusbite/services/health_service.dart';
import 'package:campusbite/services/logger_service.dart';
import 'package:campusbite/services/performance_service.dart';
import 'package:campusbite/services/update_service.dart';
import 'package:campusbite/widgets/monitored_network_image.dart';

import 'firebase_test_helper.dart';

void main() {
  group('LoggerService — structured logging (Part 4)', () {
    final captured = <String>[];
    late void Function(String) originalSink;

    setUp(() {
      originalSink = LoggerService.outputSink;
      captured.clear();
      LoggerService.outputSink = captured.add;
    });

    tearDown(() {
      LoggerService.outputSink = originalSink;
    });

    test('error logs emit the runtime type but never the raw error string', () {
      const secret = 'sensitive internal detail';
      LoggerService.instance.error('[monitoring] failure', StateError(secret));
      final joined = captured.join('\n');
      expect(joined, contains('StateError'));
      expect(joined, isNot(contains(secret)));
    });

    test('critical and warning levels carry their level tag', () {
      LoggerService.instance.critical('disk full');
      LoggerService.instance.warning('menu stale');
      final joined = captured.join('\n');
      expect(joined, contains('[critical]'));
      expect(joined, contains('[warning]'));
      expect(joined, isNot(contains('[debug]')));
    });

    test('free-form values are sanitized before emission', () {
      LoggerService.instance.debug('user ABCDEFGHIJKLMNOPQRSTUVWXYZ12 logged in');
      final joined = captured.join('\n');
      expect(joined, contains('[uid]'));
      expect(joined, isNot(contains('ABCDEFGHIJKLMNOPQRSTUVWXYZ12')));
    });

    test('AppLog facade forwards to LoggerService', () {
      AppLog.w('facade check');
      expect(captured.join('\n'), contains('facade check'));
    });
  });

  group('ErrorService — user-friendly messages (Part 3)', () {
    test('timeouts map to a retryable network message', () {
      final error = TimeoutException('late');
      expect(ErrorService.instance.categorize(error), ErrorCategory.timeout);
      expect(ErrorService.instance.isRetryable(error), isTrue);
      expect(
        ErrorService.instance.friendlyMessageFor(error),
        contains('took too long'),
      );
    });

    test('HTTP client errors map to a network message', () {
      final error = http.ClientException('connection refused');
      expect(ErrorService.instance.categorize(error), ErrorCategory.network);
      expect(
        ErrorService.instance.friendlyMessageFor(error),
        contains('Network error'),
      );
    });

    test('permission-denied maps to a permission message', () {
      final error = FirebaseException(
        plugin: 'firestore',
        code: 'permission-denied',
      );
      expect(
        ErrorService.instance.categorize(error),
        ErrorCategory.permission,
      );
      expect(
        ErrorService.instance.friendlyMessageFor(error),
        contains('permission'),
      );
    });

    test('prefixed Firebase codes are stripped before matching', () {
      final error = FirebaseException(
        plugin: 'firestore',
        code: 'firestore/permission-denied',
      );
      expect(
        ErrorService.instance.friendlyMessageFor(error),
        contains('permission'),
      );
    });

    test('server-unavailable and quota errors are retryable', () {
      final unavailable =
          FirebaseException(plugin: 'firestore', code: 'unavailable');
      final quota = FirebaseException(
        plugin: 'firestore',
        code: 'resource-exhausted',
      );
      expect(ErrorService.instance.isRetryable(unavailable), isTrue);
      expect(ErrorService.instance.isRetryable(quota), isTrue);
      expect(
        ErrorService.instance.friendlyMessageFor(unavailable),
        contains('temporarily unavailable'),
      );
      expect(
        ErrorService.instance.friendlyMessageFor(quota),
        contains('busy'),
      );
    });

    test('PlatformException codes are categorized (network/permission)', () {
      final network = PlatformException(code: 'network-request-failed');
      expect(ErrorService.instance.categorize(network), ErrorCategory.network);
      expect(
        ErrorService.instance.friendlyMessageFor(network),
        contains('Network error'),
      );
      final permission = PlatformException(code: 'permission-denied');
      expect(ErrorService.instance.categorize(permission), ErrorCategory.permission);
      expect(
        ErrorService.instance.friendlyMessageFor(permission),
        contains('permission'),
      );
      // Prefixed pigeon codes are stripped like Firebase codes.
      final prefixed = PlatformException(
        code: 'dev.flutter.plugins/channel-error',
      );
      expect(ErrorService.instance.categorize(prefixed), ErrorCategory.network);
    });

    test('unknown errors fall back to a generic message', () {
      final error = StateError('boom');
      expect(
        ErrorService.instance.friendlyMessageFor(error),
        'Something went wrong. Please try again.',
      );
      expect(ErrorService.instance.friendlyMessageFor(error), isNot(contains('boom')));
    });

    test('recordFirestoreError and recordFunctionError never throw', () {
      // Crashlytics/Analytics are unavailable in tests — must be safe no-ops.
      expect(
        () => ErrorService.instance.recordFirestoreError(
          FirebaseException(plugin: 'firestore', code: 'unavailable'),
        ),
        returnsNormally,
      );
      expect(
        () => ErrorService.instance.recordFunctionError(
          http.ClientException('down'),
        ),
        returnsNormally,
      );
    });
  });

  group('HealthService — overall status (Part 13)', () {
    test('offline connectivity reports offline', () {
      expect(
        HealthService.computeOverall(
          online: false,
          firestore: ComponentHealth.healthy,
          auth: ComponentHealth.healthy,
          cloudinary: ComponentHealth.healthy,
          notifications: ComponentHealth.healthy,
          update: ComponentHealth.healthy,
        ),
        AppHealth.offline,
      );
    });

    test('core services offline reports offline', () {
      expect(
        HealthService.computeOverall(
          online: true,
          firestore: ComponentHealth.offline,
          auth: ComponentHealth.healthy,
          cloudinary: ComponentHealth.unknown,
          notifications: ComponentHealth.unknown,
          update: ComponentHealth.unknown,
        ),
        AppHealth.offline,
      );
    });

    test('healthy core with unknown extras reports healthy', () {
      expect(
        HealthService.computeOverall(
          online: true,
          firestore: ComponentHealth.healthy,
          auth: ComponentHealth.healthy,
          cloudinary: ComponentHealth.unknown,
          notifications: ComponentHealth.unknown,
          update: ComponentHealth.unknown,
        ),
        AppHealth.healthy,
      );
    });

    test('any degraded component degrades the app', () {
      expect(
        HealthService.computeOverall(
          online: true,
          firestore: ComponentHealth.healthy,
          auth: ComponentHealth.healthy,
          cloudinary: ComponentHealth.degraded,
          notifications: ComponentHealth.healthy,
          update: ComponentHealth.healthy,
        ),
        AppHealth.degraded,
      );
    });

    test('everything unknown reports unknown', () {
      expect(
        HealthService.computeOverall(
          online: true,
          firestore: ComponentHealth.unknown,
          auth: ComponentHealth.unknown,
          cloudinary: ComponentHealth.unknown,
          notifications: ComponentHealth.unknown,
          update: ComponentHealth.unknown,
        ),
        AppHealth.unknown,
      );
    });
  });

  group('AnalyticsService — anonymous event hygiene (Part 5)', () {
    test('all event names match Firebase naming rules', () {
      final pattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
      for (final event in AnalyticsEvent.values) {
        expect(pattern.hasMatch(event.name), isTrue,
            reason: 'Bad analytics event name: ${event.name}');
      }
    });

    test('no event name can carry personal data vocabulary', () {
      const forbidden = ['email', 'uid', 'token', 'password', 'location', 'phone'];
      for (final event in AnalyticsEvent.values) {
        for (final word in forbidden) {
          expect(event.name.contains(word), isFalse,
              reason: 'Analytics event may leak PII: ${event.name}');
        }
      }
    });

    test('the parameter allow-list contains no personal keys', () {
      const forbidden = [
        // Identity & auth.
        'email',
        'uid',
        'token',
        'password',
        'location',
        'phone',
        'student_id',
        'studentId',
        'auth_token',
        'authToken',
        'id_token',
        'idToken',
        'refresh_token',
        'refreshToken',
        'fcm_token',
        'fcmToken',
        // Free-form content.
        'review_text',
        'reviewText',
        'notification_content',
        'notificationContent',
        'search_text',
        'searchText',
        // Payment.
        'payment',
        'payment_method',
        'paymentMethod',
        'card',
        'card_number',
        'cardNumber',
        'cvv',
      ];
      for (final word in forbidden) {
        expect(kAnalyticsAllowedParams.contains(word), isFalse,
            reason: 'Analytics allow-list may leak PII: $word');
      }
      expect(kAnalyticsAllowedParams, contains('category'));
      expect(kAnalyticsAllowedParams, contains('error_type'));
    });

    test('logEvent is a safe no-op when analytics is unavailable', () {
      expect(AnalyticsService.instance.isAvailable, isFalse);
      AnalyticsService.instance.logEvent(
        AnalyticsEvent.foodViewed,
        params: {'category': 'Lunch'},
      );
      AnalyticsService.instance.logScreenView('home');
    });
  });

  group('CrashReportingService — anonymous & safe (Part 1)', () {
    test('unavailable service is a safe no-op', () async {
      await CrashReportingService.instance.initialize();
      expect(CrashReportingService.instance.isAvailable, isFalse);
      CrashReportingService.instance.recordError(
        ErrorCategory.unknown,
        StackTrace.current,
      );
      CrashReportingService.instance.log('breadcrumb');
      CrashReportingService.instance.setUserRole('student');
      CrashReportingService.instance.setCurrentScreen('home');
      CrashReportingService.instance.setNetworkStatus(true);
      CrashReportingService.instance.setCustomKey('user_role', 'v');
    });

    test('custom-key values are sanitized', () {
      // Sanitization lives behind the same boundary used by Crashlytics.
      expect(
        LoggerService.sanitize('role student ABCDEFGHIJKLMNOPQRSTUVWXYZ12'),
        contains('[uid]'),
      );
    });
  });

  group('ImageMonitor — broken-URL handling (Part 10)', () {
    test('a failed URL is counted once and remembered', () {
      ImageMonitor.instance.reportFailure('https://cdn.example.com/a.jpg');
      ImageMonitor.instance.reportFailure('https://cdn.example.com/a.jpg');
      expect(ImageMonitor.instance.failedLoads, 1);
      expect(ImageMonitor.instance.brokenUrlCount, 1);
      expect(
        ImageMonitor.instance.isKnownBroken('https://cdn.example.com/a.jpg'),
        isTrue,
      );
    });

    test('successful loads update the last-success timestamp', () async {
      ImageMonitor.instance.reportLoadStart('https://cdn.example.com/b.jpg');
      ImageMonitor.instance.reportLoadEnd(
        'https://cdn.example.com/b.jpg',
        fromCache: false,
      );
      expect(ImageMonitor.instance.successfulLoads, greaterThan(0));
      expect(ImageMonitor.instance.lastSuccessAt, isNotNull);
    });

    test('placeholders are counted', () {
      final before = ImageMonitor.instance.placeholderShown;
      ImageMonitor.instance.reportPlaceholderShown();
      expect(ImageMonitor.instance.placeholderShown, before + 1);
    });
  });

  group('MonitoredNetworkImage — placeholder reporting (Part 10)', () {
    testWidgets('known-broken URL reports the placeholder exactly once per load',
        (tester) async {
      final url = 'https://cdn.example.com/broken-placeholder.jpg';
      ImageMonitor.instance.reportFailure(url);
      final before = ImageMonitor.instance.placeholderShown;

      Widget tree() => MaterialApp(
            home: Scaffold(
              body: MonitoredNetworkImage(
                imageUrl: url,
                width: 50,
                height: 50,
              ),
            ),
          );

      await tester.pumpWidget(tree());
      await tester.pump();
      expect(ImageMonitor.instance.placeholderShown, before + 1);

      // Rebuilding the same tree must not re-report the placeholder.
      await tester.pumpWidget(tree());
      await tester.pump();
      await tester.pumpWidget(tree());
      await tester.pump();
      expect(ImageMonitor.instance.placeholderShown, before + 1);
    });

    testWidgets('changing the URL resets the once-per-load placeholder guard',
        (tester) async {
      final url1 = 'https://cdn.example.com/broken-a.jpg';
      final url2 = 'https://cdn.example.com/broken-b.jpg';
      ImageMonitor.instance.reportFailure(url1);
      ImageMonitor.instance.reportFailure(url2);
      final before = ImageMonitor.instance.placeholderShown;

      Widget tree(String url) => MaterialApp(
            home: Scaffold(
              body: MonitoredNetworkImage(
                imageUrl: url,
                width: 50,
                height: 50,
              ),
            ),
          );

      await tester.pumpWidget(tree(url1));
      await tester.pump();
      expect(ImageMonitor.instance.placeholderShown, before + 1);

      // A different URL is a fresh load — placeholder is reported again.
      await tester.pumpWidget(tree(url2));
      await tester.pump();
      expect(ImageMonitor.instance.placeholderShown, before + 2);

      // Rebuilding with the same new URL still reports only once.
      await tester.pumpWidget(tree(url2));
      await tester.pump();
      expect(ImageMonitor.instance.placeholderShown, before + 2);
    });
  });

  group('DiagnosticsScreen — hidden dev screen (Part 14)', () {
    testWidgets('renders without crashing when services are unavailable',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: DiagnosticsScreen()),
      );
      await tester.pump();
      expect(find.text('Developer Diagnostics'), findsOneWidget);
      // Loading resolves (or errors gracefully) without throwing.
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  // ── Fake backends for observable-dispatch behavior tests ───────────────
  group('Injected backends — observable dispatch (Part 1/5)', () {
    late _FakeAnalyticsBackend analytics;
    late _FakeCrashlyticsBackend crashlytics;

    setUp(() {
      analytics = _FakeAnalyticsBackend();
      crashlytics = _FakeCrashlyticsBackend();
      AnalyticsService.instance.debugSetBackend(analytics);
      CrashReportingService.instance.debugSetBackend(crashlytics);
    });

    tearDown(() {
      AnalyticsService.instance.debugSetBackend(null);
      CrashReportingService.instance.debugSetBackend(null);
    });

    test('initialize enables both fake backends', () async {
      await AnalyticsService.instance.initialize();
      await CrashReportingService.instance.initialize();
      expect(AnalyticsService.instance.isAvailable, isTrue);
      expect(CrashReportingService.instance.isAvailable, isTrue);
      expect(analytics.collectionEnabled, isTrue);
      expect(crashlytics.collectionEnabled, isTrue);
    });

    test('analytics logEvent dispatches the allow-listed sanitized params',
        () async {
      await AnalyticsService.instance.initialize();
      AnalyticsService.instance.logEvent(
        AnalyticsEvent.foodViewed,
        params: {'category': 'Lunch', 'email': 'x@y.com'},
      );
      expect(analytics.events, hasLength(1));
      final event = analytics.events.single;
      expect(event.name, 'food_viewed');
      // Disallowed key dropped, allowed key kept and sanitized.
      expect(event.parameters.containsKey('email'), isFalse);
      expect(event.parameters['category'], 'Lunch');
    });

    test('analytics string values are sanitized before dispatch', () async {
      await AnalyticsService.instance.initialize();
      AnalyticsService.instance.logEvent(
        AnalyticsEvent.foodSearched,
        params: {'category': 'user ABCDEFGHIJKLMNOPQRSTUVWXYZ12'},
      );
      final value = analytics.events.single.parameters['category'] as String;
      expect(value, contains('[uid]'));
      expect(value, isNot(contains('ABCDEFGHIJKLMNOPQRSTUVWXYZ12')));
    });

    test('logScreenView dispatches the screen name only', () async {
      await AnalyticsService.instance.initialize();
      AnalyticsService.instance.logScreenView('home');
      expect(analytics.screenViews, contains('home'));
    });

    test('logEvent drops unsupported parameter value types', () async {
      await AnalyticsService.instance.initialize();
      AnalyticsService.instance.logEvent(
        AnalyticsEvent.orderPlaced,
        params: {
          'category': 'Lunch',
          'item_count': 2,
          'value': 3.5,
          'screen': <String>['a', 'b'],
          'host': {'nested': 'map'},
          'result': DateTime.now(),
          'stage': true,
        },
      );
      final event = analytics.events.single;
      // String and num values survive.
      expect(event.parameters['category'], 'Lunch');
      expect(event.parameters['item_count'], 2);
      expect(event.parameters['value'], 3.5);
      // Lists, maps, objects and booleans are dropped.
      expect(event.parameters.containsKey('screen'), isFalse);
      expect(event.parameters.containsKey('host'), isFalse);
      expect(event.parameters.containsKey('result'), isFalse);
      expect(event.parameters.containsKey('stage'), isFalse);
    });

    test('logEvent drops prohibited keys at the emission boundary', () async {
      await AnalyticsService.instance.initialize();
      AnalyticsService.instance.logEvent(
        AnalyticsEvent.orderPlaced,
        params: {
          'category': 'Lunch',
          'error_type': 'none',
          'student_id': 's123',
          'review_text': 'yummy',
          'notification_content': 'your order is ready',
          'search_text': 'burger',
          'payment_method': 'card',
          'card_number': '4242',
          'auth_token': 'abc',
          'refresh_token': 'xyz',
          'fcm_token': 'fcmABC',
        },
      );
      final event = analytics.events.single;
      // Allowed keys survive.
      expect(event.parameters['category'], 'Lunch');
      expect(event.parameters['error_type'], 'none');
      // Prohibited keys are rejected before reaching the backend.
      const prohibited = [
        'student_id',
        'review_text',
        'notification_content',
        'search_text',
        'payment_method',
        'card_number',
        'auth_token',
        'refresh_token',
        'fcm_token',
      ];
      for (final key in prohibited) {
        expect(event.parameters.containsKey(key), isFalse,
            reason: 'Prohibited key leaked to analytics backend: $key');
      }
    });

    test('crash recordError forwards only the category, never raw error text',
        () async {
      await CrashReportingService.instance.initialize();
      final stack = StackTrace.current;
      CrashReportingService.instance.recordError(
        ErrorCategory.network,
        stack,
        fatal: true,
      );
      expect(crashlytics.recordedErrors, hasLength(1));
      final record = crashlytics.recordedErrors.single;
      // Only the category label reaches the backend — no exception text.
      expect(record.category, 'network');
      expect(record.stack, same(stack));
      expect(record.fatal, isTrue);
    });

    test('setCustomKey ignores keys outside the approved set', () async {
      await CrashReportingService.instance.initialize();
      CrashReportingService.instance.setCustomKey('email', 'a@b.com');
      CrashReportingService.instance.setCustomKey('uid', 'ABC123');
      CrashReportingService.instance.setCustomKey('user_role', 'student');
      // Approved key passes through; disallowed keys are dropped before the
      // backend (initialize() also records platform/sdk_version context).
      expect(crashlytics.customKeys['user_role'], 'student');
      expect(crashlytics.customKeys.containsKey('email'), isFalse);
      expect(crashlytics.customKeys.containsKey('uid'), isFalse);
      expect(kApprovedCrashKeys, contains('user_role'));
    });

    test('crash custom keys are sanitized before dispatch', () async {
      await CrashReportingService.instance.initialize();
      CrashReportingService.instance.setCustomKey(
        'user_role',
        'admin ABCDEFGHIJKLMNOPQRSTUVWXYZ12',
      );
      final value = crashlytics.customKeys['user_role']!;
      expect(value, contains('[uid]'));
      expect(value, isNot(contains('ABCDEFGHIJKLMNOPQRSTUVWXYZ12')));
    });

    test('ErrorService zone errors reach the crash backend by category',
        () async {
      await CrashReportingService.instance.initialize();
      ErrorService.instance.handleZoneError(
        StateError('uncaught async'),
        StackTrace.current,
      );
      expect(crashlytics.recordedErrors, hasLength(1));
      // A generic StateError maps to the non-identifying 'unknown' category;
      // the raw error text never reaches the backend.
      expect(crashlytics.recordedErrors.single.category, 'unknown');
      expect(
        crashlytics.recordedErrors.single.category,
        isNot(contains('uncaught')),
      );
    });

    test('ErrorService Flutter errors reach crash + analytics', () async {
      await AnalyticsService.instance.initialize();
      await CrashReportingService.instance.initialize();
      final details = FlutterErrorDetails(
        exception: StateError('layout'),
        library: 'test',
      );
      ErrorService.instance.handleFlutterError(details);
      expect(crashlytics.recordedErrors, hasLength(1));
      expect(crashlytics.recordedErrors.single.category, 'unknown');
      expect(analytics.events.any((e) => e.name == 'error_occurred'), isTrue);
    });

    test('recordFirestoreError reports the category via analytics', () async {
      await AnalyticsService.instance.initialize();
      await CrashReportingService.instance.initialize();
      ErrorService.instance.recordFirestoreError(
        FirebaseException(plugin: 'firestore', code: 'unavailable'),
      );
      expect(analytics.events.any((e) => e.name == 'firestore_error'), isTrue);
      expect(crashlytics.breadcrumbs, isNotEmpty);
    });

    test('recordFunctionError writes a crash breadcrumb', () async {
      await CrashReportingService.instance.initialize();
      ErrorService.instance.recordFunctionError(http.ClientException('down'));
      expect(
        crashlytics.breadcrumbs.any((b) => b.contains('function error')),
        isTrue,
      );
    });

    test('rejected backend futures are consumed, never unhandled', () async {
      await CrashReportingService.instance.initialize();
      CrashReportingService.instance.debugSetBackend(
        _RejectingCrashlyticsBackend(),
      );
      await CrashReportingService.instance.initialize();
      // None of these may surface an unhandled async error.
      CrashReportingService.instance.recordError(
        ErrorCategory.unknown,
        StackTrace.current,
      );
      CrashReportingService.instance.recordFlutterError(
        ErrorCategory.unknown,
        StackTrace.current,
      );
      CrashReportingService.instance.log('breadcrumb');
      CrashReportingService.instance.setCustomKey('user_role', 'admin');
      CrashReportingService.instance.setUserRole('admin');
      // Let the rejected futures' error handlers run before the test ends.
      await Future<void>.delayed(Duration.zero);
    });

    test('rejected analytics futures are consumed, never unhandled',
        () async {
      await AnalyticsService.instance.initialize();
      AnalyticsService.instance.debugSetBackend(_RejectingAnalyticsBackend());
      await AnalyticsService.instance.initialize();
      // None of these may surface an unhandled async error.
      AnalyticsService.instance.logEvent(AnalyticsEvent.foodViewed);
      AnalyticsService.instance.logScreenView('home');
      // Let the rejected futures' error handlers run before the test ends.
      await Future<void>.delayed(Duration.zero);
    });

    test('rejected logging call marks analytics unavailable and re-initializes',
        () async {
      await AnalyticsService.instance.initialize();
      AnalyticsService.instance.debugSetBackend(_RejectingAnalyticsBackend());
      await AnalyticsService.instance.initialize();
      expect(AnalyticsService.instance.isAvailable, isTrue);

      // A logging call whose backend future rejects must flip availability
      // off so recovery is scheduled instead of silently ignoring the fault.
      AnalyticsService.instance.logEvent(AnalyticsEvent.foodViewed);
      await Future<void>.delayed(Duration.zero);
      expect(AnalyticsService.instance.isAvailable, isFalse);

      // Restore a healthy backend and re-initialize: analytics recovers and
      // subsequent events flow again.
      AnalyticsService.instance.debugSetBackend(analytics);
      await AnalyticsService.instance.initialize();
      expect(AnalyticsService.instance.isAvailable, isTrue);
      AnalyticsService.instance.logEvent(AnalyticsEvent.foodViewed);
      expect(analytics.events.any((e) => e.name == 'food_viewed'), isTrue);
    });
  });

  // ── Trace lifecycle + restart recovery (Part 6) ─────────────────────────
  group('PerformanceService — trace lifecycle (Part 6)', () {
    late List<_FakeTraceHandle> created;

    setUp(() {
      created = [];
      PerformanceService.instance.debugSetAvailable(true);
      PerformanceService.instance.debugSetTraceFactory((name) {
        final handle = _FakeTraceHandle();
        created.add(handle);
        return handle.build();
      });
    });

    tearDown(() {
      PerformanceService.instance.debugSetTraceFactory(null);
      PerformanceService.instance.debugSetAvailable(false);
    });

    test('startTrace creates a handle that records stop and metrics', () {
      final handle = PerformanceService.instance.startTrace(kTraceMenuLoad);
      expect(handle, isNotNull);
      expect(created, hasLength(1));
      handle!.incrementMetric(kMetricMenuLoadDocs, 3);
      expect(created.single.metrics[kMetricMenuLoadDocs], 3);
      handle.stop();
      expect(created.single.stopped, isTrue);
    });

    test('restart recovery: a stopped trace is never reused', () {
      final first = PerformanceService.instance.startTrace(kTraceMenuLoad);
      first!.stop();
      final second = PerformanceService.instance.startTrace(kTraceMenuLoad);
      expect(identical(first, second), isFalse);
      expect(created, hasLength(2));
      expect(created[0].stopped, isTrue);
      expect(created[1].stopped, isFalse);
    });

    test('startTrace returns null while unavailable', () {
      PerformanceService.instance.debugSetAvailable(false);
      expect(PerformanceService.instance.startTrace(kTraceMenuLoad), isNull);
      expect(created, isEmpty);
    });

    test('startTrace rejects identifiers outside the approved set', () {
      // A sensitive identifier (UID, order ID, search text) must never
      // become a Firebase Performance trace name.
      expect(
        PerformanceService.instance.startTrace('user_ABC123_order_42'),
        isNull,
      );
      expect(created, isEmpty);
    });

    test('incrementMetric rejects unapproved names and out-of-range values', () {
      final handle = PerformanceService.instance.startTrace(kTraceMenuLoad);
      handle!.incrementMetric('user_id', 3);
      handle.incrementMetric(kMetricMenuLoadDocs, -1);
      handle.incrementMetric(kMetricMenuLoadDocs, kMaxMetricValue + 1);
      // Nothing reached the SDK for any rejected call.
      expect(created.single.metrics, isEmpty);
      // An approved, in-range value still passes.
      handle.incrementMetric(kMetricMenuLoadDocs, 2);
      expect(created.single.metrics[kMetricMenuLoadDocs], 2);
    });
  });

  // ── Update & Cloudinary monitoring (Parts 10/14) ────────────────────────
  group('Update & Cloudinary monitoring (Parts 10/14)', () {
    late _FakeAnalyticsBackend analytics;

    setUp(() {
      analytics = _FakeAnalyticsBackend();
      AnalyticsService.instance.debugSetBackend(analytics);
    });

    tearDown(() {
      AnalyticsService.instance.debugSetBackend(null);
    });

    test('Cloudinary image failures dispatch image_load_failed with host only',
        () async {
      await AnalyticsService.instance.initialize();
      ImageMonitor.instance
          .reportFailure('https://res.cloudinary.com/foo/bar/image.jpg');
      final event =
          analytics.events.singleWhere((e) => e.name == 'image_load_failed');
      expect(event.parameters['host'], 'res.cloudinary.com');
      expect(event.parameters['host'], isNot(contains('bar')));
    });

    test('update decisions map to the reported update states', () {
      expect(
        UpdateService.decideState(
          current: '1.0.0',
          remoteVersion: '1.0.1',
          minimumVersion: '1.0.0',
          forceUpdate: false,
        ),
        UpdateState.updateAvailable,
      );
      expect(
        UpdateService.decideState(
          current: '1.0.0',
          remoteVersion: '1.0.1',
          minimumVersion: '1.1.0',
          forceUpdate: false,
        ),
        UpdateState.updateRequired,
      );
      expect(
        UpdateService.decideState(
          current: '1.0.0',
          remoteVersion: '1.0.1',
          minimumVersion: '1.0.0',
          forceUpdate: true,
        ),
        UpdateState.updateRequired,
      );
    });

    test('update_available dispatches through the analytics backend',
        () async {
      await AnalyticsService.instance.initialize();
      AnalyticsService.instance.logEvent(
        AnalyticsEvent.updateAvailable,
        params: {'result': 'optional'},
      );
      final event =
          analytics.events.singleWhere((e) => e.name == 'update_available');
      expect(event.parameters['result'], 'optional');
    });
  });

  // ── DiagnosticsEntryTile visibility (Part 14) ───────────────────────────
  group('DiagnosticsEntryTile — visibility gating (Part 14)', () {
    test('debug builds always show the entry regardless of role', () {
      expect(
        DiagnosticsEntryTile.shouldShowDiagnostics(
          debugMode: true,
          role: 'student',
        ),
        isTrue,
      );
    });

    test('release-like builds hide the entry for students', () {
      expect(
        DiagnosticsEntryTile.shouldShowDiagnostics(
          debugMode: false,
          role: 'student',
        ),
        isFalse,
      );
    });

    test('release-like builds show the entry for administrators', () {
      expect(
        DiagnosticsEntryTile.shouldShowDiagnostics(
          debugMode: false,
          role: 'admin',
        ),
        isTrue,
      );
    });

    testWidgets('entry tile renders in debug builds', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DiagnosticsEntryTile())),
      );
      await tester.pump();
      expect(find.text('Developer Diagnostics'), findsOneWidget);
    });
  });

  group('Static guardrails (Part 17)', () {
    String readRepoFile(String path) =>
        File(path).readAsStringSync();

    test('no print/debugPrint anywhere in lib, logger included', () {
      // LoggerService emits through its own outputSink (dart:developer log),
      // so no file — including the logger itself — may call print/debugPrint.
      final lib = Directory('lib');
      for (final entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        expect(
          source.contains('debugPrint(') || source.contains('print('),
          isFalse,
          reason: 'Direct print in ${entity.path} — use LoggerService',
        );
      }
    });

    test('monitoring services never write to Firestore', () {
      const files = [
        'lib/services/error_service.dart',
        'lib/services/analytics_service.dart',
        'lib/services/performance_service.dart',
        'lib/services/crash_reporting_service.dart',
        'lib/services/health_service.dart',
        'lib/services/diagnostics_service.dart',
        'lib/services/logger_service.dart',
        'lib/widgets/monitored_network_image.dart',
        'lib/screens/diagnostics_screen.dart',
      ];
      // Firestore writes appear as collection(...)/doc(...).<write>(...); a
      // bare `.add(`/`.set(` can be a Dart Set/Map call, so require the
      // Firestore context.
      final writePattern = RegExp(
        r'collection\s*\([^;]*?\.(?:set|add|update|delete)\s*\(|'
        r'\.doc\s*\([^;]*?\.(?:set|update|delete)\s*\(|'
        r'runTransaction\s*\(',
      );
      for (final path in files) {
        final source = readRepoFile(path);
        expect(
          writePattern.hasMatch(source),
          isFalse,
          reason: '$path must not write monitoring data to Firestore',
        );
      }
    });

    test('pubspec includes the Phase 17 monitoring packages', () {
      final pubspec = readRepoFile('pubspec.yaml');
      expect(pubspec, contains('firebase_crashlytics'));
      expect(pubspec, contains('firebase_analytics'));
      expect(pubspec, contains('firebase_performance'));
    });

    test('error handlers install in ErrorService and wire into main', () {
      final errorSource = readRepoFile('lib/services/error_service.dart');
      expect(errorSource, contains('FlutterError.onError'));
      expect(errorSource, contains('PlatformDispatcher.instance.onError'));

      final mainSource = readRepoFile('lib/main.dart');
      expect(mainSource, contains('ErrorService.instance.init()'));
      expect(mainSource, contains('runZonedGuarded'));
      expect(mainSource, contains('beginAppStartup'));
      expect(mainSource, contains('endAppStartup'));
    });

    test('diagnostics entry is gated on debug builds or admin role', () {
      final viewModel =
          readRepoFile('lib/viewmodels/diagnostics_view_model.dart');
      expect(viewModel, contains('kDebugMode'));
      expect(viewModel, contains("role == 'admin'"));
    });

    test('update service reports monitoring events', () {
      final update = readRepoFile('lib/services/update_service.dart');
      expect(update, contains('AnalyticsEvent.updateAvailable'));
      expect(update, contains('AnalyticsEvent.updateDownloadFailed'));
      expect(update, contains('AnalyticsEvent.updateVerificationFailed'));
    });

    test('Crashlytics proguard keeps source lines', () {
      final proguard = readRepoFile('android/app/proguard-rules.pro');
      expect(proguard, contains('SourceFile,LineNumberTable'));
      expect(proguard, contains('com.google.firebase.crashlytics.**'));
    });

    test('FoodData.resetStreams stops and clears the menu-load trace', () {
      final foodData = readRepoFile('lib/data/food_data.dart');
      final reset = foodData.substring(
        foodData.indexOf('static void resetStreams()'),
      );
      expect(reset, contains('_menuLoadTrace?.stop()'));
      expect(reset, contains('_menuLoadTrace = null'));
    });

    test('router handles unmatched routes with an explicit errorBuilder', () {
      final routerSource = readRepoFile('lib/navigation/router.dart');
      expect(routerSource, contains('errorBuilder:'));
      expect(routerSource, contains('NotFoundScreen'));
    });

    testWidgets('unknown routes render the not-found screen', (tester) async {
      await setupFirebaseForTest();
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      // Navigate to a route that does not exist — the errorBuilder must render
      // the friendly NotFoundScreen instead of throwing.
      router.go('/definitely-not-a-route');
      await tester.pumpAndSettle();
      expect(find.text('The page you are looking for does not exist.'),
          findsOneWidget);
      expect(find.text('Go Home'), findsOneWidget);
    });
  });
}

// ── Fake backends ───────────────────────────────────────────────────────────

class _FakeAnalyticsBackend implements AnalyticsBackend {
  bool collectionEnabled = false;
  final events = <_FakeAnalyticsEvent>[];
  final screenViews = <String>[];

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    collectionEnabled = enabled;
  }

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    events.add(
      _FakeAnalyticsEvent(name, Map<String, Object>.of(parameters)),
    );
  }

  @override
  Future<void> logScreenView(String screenName) async {
    screenViews.add(screenName);
  }
}

class _FakeAnalyticsEvent {
  _FakeAnalyticsEvent(this.name, this.parameters);

  final String name;
  final Map<String, Object> parameters;
}

class _FakeCrashlyticsBackend implements CrashlyticsBackend {
  bool collectionEnabled = false;
  final recordedErrors = <_FakeCrashRecord>[];
  final breadcrumbs = <String>[];
  final customKeys = <String, String>{};

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    collectionEnabled = enabled;
  }

  @override
  Future<void> recordError(
    String category,
    StackTrace stack, {
    required bool fatal,
  }) async {
    recordedErrors.add(_FakeCrashRecord(category, stack, fatal));
  }

  @override
  Future<void> log(String message) async {
    breadcrumbs.add(message);
  }

  @override
  Future<void> setCustomKey(String key, String value) async {
    customKeys[key] = value;
  }
}

/// Backend whose analytics methods always reject — used to prove the
/// service consumes rejected futures instead of leaving them unhandled.
class _RejectingAnalyticsBackend implements AnalyticsBackend {
  @override
  Future<void> setCollectionEnabled(bool enabled) async {}

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    throw StateError('backend reject');
  }

  @override
  Future<void> logScreenView(String screenName) async {
    throw StateError('backend reject');
  }
}

/// Backend whose reporting methods always reject — used to prove the
/// service consumes rejected futures instead of leaving them unhandled.
class _RejectingCrashlyticsBackend implements CrashlyticsBackend {
  @override
  Future<void> setCollectionEnabled(bool enabled) async {}

  @override
  Future<void> recordError(
    String category,
    StackTrace stack, {
    required bool fatal,
  }) async {
    throw StateError('backend reject');
  }

  @override
  Future<void> log(String message) async {
    throw StateError('backend reject');
  }

  @override
  Future<void> setCustomKey(String key, String value) async {
    throw StateError('backend reject');
  }
}

class _FakeCrashRecord {
  _FakeCrashRecord(this.category, this.stack, this.fatal);

  final String category;
  final StackTrace stack;
  final bool fatal;
}

class _FakeTraceHandle {
  bool stopped = false;
  final metrics = <String, int>{};

  TraceHandle build() => TraceHandle.testing(
        stopCallback: () => stopped = true,
        incrementCallback: (name, value) =>
            metrics[name] = (metrics[name] ?? 0) + value,
      );
}
