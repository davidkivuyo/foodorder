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

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/data/food_data.dart';
import 'package:campusbite/services/auth_service.dart';
import 'package:campusbite/services/cart_service.dart';

/// Phase 15 — Parts 3, 5, 7, 8, 11, 12, 14, 20, 21 (security hardening).
///
/// Two layers of coverage:
///   1. Unit tests for authentication hardening (anti-enumeration).
///   2. Static guardrail tests that read the shipped security artifacts
///      (firestore.rules, functions/index.js, lib/main.dart, CI workflows)
///      and assert the Phase 15 invariants survive refactors. These run in
///      CI (`flutter test`) before every release so a regression in a rule,
///      a Cloud Function, an App Check guard, or the update host allowlist
///      fails the pipeline instead of shipping.
void main() {
  group('AuthService.userFacingSignInError — anti-enumeration', () {
    FirebaseAuthException authError(String code) =>
        FirebaseAuthException(code: code, message: 'message for $code');

    test('unknown email and wrong password produce the SAME message', () {
      final unknownEmail = AuthService.userFacingSignInError(
        authError('user-not-found'),
      );
      final wrongPassword = AuthService.userFacingSignInError(
        authError('wrong-password'),
      );
      final invalidCredential = AuthService.userFacingSignInError(
        authError('invalid-credential'),
      );
      final invalidLoginCredentials = AuthService.userFacingSignInError(
        authError('invalid-login-credentials'),
      );
      final disabled = AuthService.userFacingSignInError(
        authError('user-disabled'),
      );

      final generic = 'Invalid email or password. Please try again.';
      expect(unknownEmail, generic);
      expect(wrongPassword, generic);
      expect(invalidCredential, generic);
      expect(invalidLoginCredentials, generic);
      expect(disabled, generic);
    });

    test('message does not contain the Firebase error code', () {
      final msg = AuthService.userFacingSignInError(
        authError('user-not-found'),
      );
      expect(msg, isNot(contains('user-not-found')));
      expect(msg, isNot(contains('wrong-password')));
    });

    test('rate limiting keeps a helpful but non-enumerating message', () {
      final msg = AuthService.userFacingSignInError(
        authError('too-many-requests'),
      );
      expect(
        msg,
        'Too many failed attempts. Please wait a moment and try again.',
      );
    });

    test('network failures are reported generically', () {
      final msg = AuthService.userFacingSignInError(
        authError('network-request-failed'),
      );
      expect(msg, 'Network error. Please check your internet connection.');
    });

    test('unknown Firebase codes fall back to a generic message', () {
      final msg = AuthService.userFacingSignInError(
        authError('some-unknown-code'),
      );
      expect(msg, 'Authentication failed. Please try again.');
    });

    test('PlatformException codes are handled (pigeon bridge)', () {
      final platformError = PlatformException(
        code: 'firebase_auth/user-not-found',
        details: <String, Object>{'code': 'firebase_auth/user-not-found'},
      );
      final msg = AuthService.userFacingSignInError(platformError);
      expect(msg, 'Invalid email or password. Please try again.');
    });
  });

  // ── Static guardrail helpers ──────────────────────────────────────────────

  String readRepoFile(String path) => File(path).readAsStringSync();

  // ── Firestore Rules — authorization boundaries (Part 2/3) ────────────────
  //
  // firestore.rules is tracked in the repository, so it is present in CI
  // checkouts and these guardrails always run — a regression must fail the
  // release, never ship.

  group(
    'Firestore security rules — least privilege',
    () {
      late String rules;
      setUpAll(() {
        rules = readRepoFile('firestore.rules');
      });

      test('no collection is wide-open (allow read, write: if true)', () {
        expect(rules, isNot(contains('allow read, write: if true;')));
        expect(rules, isNot(contains('allow read, write: if true')));
      });

      test('role helper functions exist (isAuth / isOwner / isAdmin)', () {
        expect(rules, contains('function isAuth()'));
        expect(rules, contains('function isOwner('));
        expect(rules, contains('function isAdmin()'));
      });

      test('food_items writes are admin-only (Part 4)', () {
        final foodBlock = rules.substring(
          rules.indexOf('match /food_items/{docId}'),
          rules.indexOf('match /categories/{docId}'),
        );
        expect(foodBlock, contains('allow create: if isAdmin()'));
        expect(foodBlock, contains('allow update: if isAdmin()'));
        expect(foodBlock, contains('allow delete: if isAdmin()'));
        // Students must never modify the menu.
        expect(foodBlock, isNot(contains('allow update: if isAuth()')));
      });

      test(
        'reviews enforce ownership and COLLECTED-order eligibility (Part 7)',
        () {
          final reviewBlock = rules.substring(
            rules.indexOf('match /reviews/{docId}'),
            rules.indexOf('match /device_tokens/{docId}'),
          );
          // Only the author may update their own review.
          expect(
            reviewBlock,
            contains('resource.data.userId == request.auth.uid'),
          );
          expect(reviewBlock, contains('validReviewOrderEligibility()'));
          expect(reviewBlock, contains('reviewCompositeId('));
          expect(reviewBlock, contains('allow delete: if false;'));
          // The eligibility rule must require a populated foodIds list that
          // contains the reviewed food — no legacy fallback (Part 7).
          expect(
            rules,
            contains('order.data.foodIds is list'),
          );
          expect(
            rules,
            contains('order.data.foodIds.hasAny([request.resource.data.foodId])'),
          );
        },
      );

      test('audit_logs are admin-append-only (Part 20)', () {
        final auditBlock = rules.substring(
          rules.indexOf('match /audit_logs/{docId}'),
          rules.indexOf('match /users/{userId}'),
        );
        expect(auditBlock, contains('allow create: if isAdmin()'));
        expect(auditBlock, contains('validAuditLogCreate()'));
        expect(auditBlock, contains('allow update: if false;'));
        expect(auditBlock, contains('allow delete: if false;'));
        // Admins may only log actions as themself — no spoofing another admin
        // or the automation engine ("system").
        final auditFn = rules.substring(
          rules.indexOf('function validAuditLogCreate()'),
          rules.indexOf('// ── Rules ─'),
        );
        expect(auditFn, contains('request.auth.uid'));
        expect(
          auditFn,
          contains("request.resource.data.adminId == request.auth.uid"),
        );
        expect(
          auditFn,
          contains("request.resource.data.performedBy == request.auth.uid"),
        );
      });

      test('orders are owner-scoped and admin-gated (Part 10)', () {
        final orderBlock = rules.substring(
          rules.indexOf('match /orders/{docId}'),
          rules.indexOf('match /section/{sectionId}'),
        );
        expect(orderBlock, contains('isOwner('));
        expect(orderBlock, contains('validOrderCreateRequest()'));
        expect(orderBlock, contains('adminNotModifyingProtectedOrderFields()'));
        // Illegal/backwards status transitions must be rejected (Part 10).
        expect(orderBlock, contains('validOrderStatusTransition()'));
        expect(rules, contains('function canonicalOrderStatus(status)'));
        expect(rules, contains('function validOrderStatusTransition()'));
      });

      test('strike data is immutable for students (Part 8)', () {
        // Students may never modify strike counters or suspension status —
        // only admins via validAdminStrikeUpdate().
        expect(rules, contains('studentNotModifyingProtectedFields()'));
        expect(rules, contains('validAdminStrikeUpdate()'));
        final usersUpdate = rules.substring(
          rules.indexOf('match /users/{userId}'),
          rules.indexOf('match /user/{userId}'),
        );
        expect(usersUpdate, contains("allow update: if (isOwner(userId)"));
        expect(usersUpdate, contains('studentNotModifyingProtectedFields()'));
        expect(usersUpdate, contains('validAdminStrikeUpdate()'));
      });

      test('students cannot change their role (Part 21 checklist)', () {
        // A student who could edit `role` could self-promote to admin.
        // studentNotModifyingProtectedFields() must therefore keep `role` off
        // the student-editable allowlist.
        final fn = rules.substring(
          rules.indexOf('function studentNotModifyingProtectedFields()'),
          rules.indexOf('function validUserCreateRequest()'),
        );
        expect(
          fn,
          contains(
            "let allowed = ['fullName', 'email', 'phoneNumber', 'cafeName'];",
          ),
        );
        // role / strikeCount / accountStatus must NOT be student-writable.
        expect(fn, isNot(contains("'role'")));
        expect(fn, isNot(contains("'strikeCount'")));
        expect(fn, isNot(contains("'accountStatus'")));
        // A changed email must equal the verified ID-token email claim.
        expect(
          fn,
          contains('request.resource.data.email == request.auth.token.email'),
        );
      });

      test('student profile email must match the ID-token email claim', () {
        // A student creating their own profile cannot forge an email that
        // differs from the one in their verified ID token (Part 3).
        final fn = rules.substring(
          rules.indexOf('function validUserCreateRequest()'),
          rules.indexOf('function validFavoriteMenuUpdate()'),
        );
        expect(
          fn,
          contains('request.resource.data.email == request.auth.token.email'),
        );
        // Exempt admins (admin creation gated by isAdmin(), not the claim).
        expect(fn, contains('!isStudentRole'));
      });

      test('notifications are owner-scoped, admin-created only (Part 9)', () {
        final notifBlock = rules.substring(
          rules.indexOf('match /notifications/{docId}'),
          rules.indexOf('match /delivery_records/{docId}'),
        );
        expect(notifBlock, contains('isOwner(resource.data.recipientId)'));
        expect(notifBlock, contains("'recipientId' in resource.data"));
        expect(notifBlock, contains('validNotificationCreate()'));
        expect(notifBlock, contains('allow create: if isAdmin() && validNotificationCreate();'));
        // Students may only toggle read/deleted flags on their own.
        expect(
          notifBlock,
          contains("['read', 'readAt', 'deleted', 'deletedAt']"),
        );
        expect(notifBlock, contains('allow delete: if false;'));
      });

      test('cart lives under users/{userId} (Part 3 ownership by path)', () {
        // The cart sub-collection is defined inside the users/{userId} match,
        // so a student's cart is inherently scoped to their own document.
        expect(rules, contains('match /cart/{itemId}'));
        // Bound the plural /users/{userId} block with its closing sibling
        // (the singular /user/{userId} match), then assert the cart match
        // falls within that range — not merely after the block's start.
        final usersStart = rules.indexOf('match /users/{userId}');
        final usersEnd = rules.indexOf('match /user/{userId}');
        final cartMatch = rules.indexOf('match /cart/{itemId}');
        expect(cartMatch, greaterThan(usersStart));
        expect(cartMatch, lessThan(usersEnd));
      });
    },
  );

  // ── Cloud Functions — invalid request rejection (Part 5) ─────────────────

  group('Cloud Functions security — server-side validation', () {
    late String fn;
    setUpAll(() {
      fn = readRepoFile('functions/index.js');
    });

    test('invalid requests are rejected with HttpsError', () {
      expect(fn, contains('new HttpsError('));
      expect(
        fn.contains('"invalid-argument"'),
        isTrue,
        reason: 'malformed/oversized payloads must map to invalid-argument',
      );
    });

    test('callables verify request.auth before privileged operations', () {
      expect(fn, contains('request.auth'));
      expect(fn, contains('throw new HttpsError('));
    });

    test('Cloudinary deletion uses a Cloud Function, never a client secret '
        '(Part 12)', () {
      // The API secret must come from Secret Manager at runtime.
      expect(fn, contains('defineSecret("CLOUDINARY_API_SECRET")'));
      expect(fn, contains('CLOUDINARY_API_SECRET.value()'));
      // The secret is only ever read from Secret Manager — never assigned a
      // literal value in source.
      expect(fn, isNot(contains('apiSecret = "')));
    });

    test(
      'admin account gate checks ACTIVE status with no default (Part 4)',
      () {
        // deleteCloudinaryImage must require accountStatus exactly "ACTIVE" —
        // missing/null values are denied, never defaulted.
        expect(
          fn,
          contains('accountStatus !== "ACTIVE"'),
          reason: 'missing status must not default to ACTIVE',
        );
      },
    );

    test('audit logs are written for privileged actions (Part 20)', () {
      expect(fn, contains('collection("audit_logs")'));
      expect(fn, contains('timestamp:'));
      expect(fn, contains('action:'));
      expect(fn, contains('performedBy:'));
    });
  });

  // ── App Check — enforcement & fail-closed behavior (Part 1) ──────────────

  group('App Check enforcement', () {
    test('web release build fails closed without a reCAPTCHA key', () {
      final main = readRepoFile('lib/main.dart');
      expect(
        main,
        contains('kIsWeb && !kDebugMode && kRecaptchaSiteKey.isEmpty'),
      );
      expect(main, contains('_AppCheckMisconfiguredApp'));
    });

    test('Android release uses Play Integrity, debug uses debug provider', () {
      final main = readRepoFile('lib/main.dart');
      expect(main, contains('AndroidPlayIntegrityProvider'));
      expect(main, contains('AndroidDebugProvider'));
      expect(main, contains('ReCaptchaV3Provider'));
    });

    test('web deploy workflow refuses to build without RECAPTCHA_SITE_KEY', () {
      final deploy = readRepoFile('.github/workflows/deploy.yml');
      expect(deploy, contains('RECAPTCHA_SITE_KEY'));
      expect(deploy, contains('exit 1'));
    });
  });

  // ── Update system — host allowlist & checksum verification (Part 11) ─────

  group('Update system security', () {
    test('only the dl.larason.space host is allowed for downloads', () {
      // Behavioral coverage lives in update_security_test.dart; this guard
      // ensures the allowlist survives refactors.
      final svc = readRepoFile('lib/services/update_service.dart');
      expect(svc, contains("allowedHost = 'dl.larason.space'"));
      expect(svc, contains('isAllowedDownloadUrl'));
    });

    test(
      'installer fails closed when the checksum is missing or mismatched',
      () {
        final svc = readRepoFile('lib/services/update_service.dart');
        expect(svc, contains('No checksum to compare — fail closed'));
        expect(svc, contains("_fail('Could not verify the update.')"));
        expect(svc, contains('checksum mismatch — installer discarded'));
      },
    );
  });

  // ── Secret scanning (Part 13) ─────────────────────────────────────────────

  group('Secret scanning — no secrets in source', () {
    test('no private keys or signing material in lib/ or workflows', () {
      // Walk the whole lib/ tree (excluding build artifacts) so a secret
      // introduced into ANY new Dart file fails the pipeline.
      final libDirs = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in libDirs) {
        final src = file.readAsStringSync();
        expect(
          src,
          isNot(contains('-----BEGIN')),
          reason: '${file.path} must not embed private keys',
        );
        expect(
          src,
          isNot(contains('sk_live_')),
          reason: '${file.path} must not embed Stripe live keys',
        );
        expect(
          src,
          isNot(contains('cloudinary_api_secret')),
          reason: '${file.path} must not embed Cloudinary credentials',
        );
      }
      final deploy = readRepoFile('.github/workflows/deploy.yml');
      final release = readRepoFile('.github/workflows/release-apk.yml');
      expect(deploy + release, isNot(contains('-----BEGIN')));
    });

    test('no Cloudinary API secret literal in functions source', () {
      // The secret only ever comes from Secret Manager (defineSecret).
      final fn = readRepoFile('functions/index.js');
      expect(fn, isNot(contains('CLOUDINARY_API_SECRET = "')));
    });
  });

  // ── Release-build behavior (Part 21) ─────────────────────────────────────

  group('Release-build behavior', () {
    test('the app ships zero GitHub references (update system proxy rule)', () {
      // The update system may only talk to dl.larason.space; GitHub must
      // never appear in app code.
      final main = readRepoFile('lib/main.dart');
      expect(main, isNot(contains('github.com')));
    });

    test('release pipeline runs the security test suite before building', () {
      final release = readRepoFile('.github/workflows/release-apk.yml');
      final testStep = release.indexOf('flutter test');
      expect(testStep, isNot(-1), reason: 'release workflow must run tests');
      expect(
        testStep,
        lessThan(release.indexOf('Build Universal APK')),
        reason: 'tests must run BEFORE building',
      );
    });

    test(
      'web deploy pipeline runs the security test suite before building',
      () {
        final deploy = readRepoFile('.github/workflows/deploy.yml');
        final testStep = deploy.indexOf('flutter test');
        expect(testStep, isNot(-1), reason: 'deploy workflow must run tests');
        expect(
          testStep,
          lessThan(deploy.indexOf('flutter build web')),
          reason: 'tests must run BEFORE the web build',
        );
      },
    );
  });

  // ── Behavioral authorization boundary (Part 3) ───────────────────────────

  group('CartService — user-scoped writes (authorization boundary)', () {
    testWidgets('cart items are written under the authenticated user doc', (
      WidgetTester tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      final service = CartService.testing(
        firestore: firestore,
        userId: 'user_A',
      );

      final item = FoodItem(
        id: 'food_001',
        image: 'https://example.com/img.jpg',
        title: 'Test Item',
        titleLower: 'test item',
        subtitle: 'Test subtitle',
        description: 'Test description',
        price: 5000,
        rating: 4.0,
        category: 'Test',
        availableCafes: const ['Cafe A'],
        time: '10 min',
        section: 'test',
        available: true,
        quantity: 99,
      );

      final added = await service.addToCart(item, selectedCafe: 'Cafe A');
      expect(added, isTrue);

      // The write must land under /users/user_A/cart, never a global path.
      final userACart = await firestore
          .collection('users')
          .doc('user_A')
          .collection('cart')
          .get();
      expect(userACart.docs, isNotEmpty);

      // Another user's cart stays untouched.
      final userBCart = await firestore
          .collection('users')
          .doc('user_B')
          .collection('cart')
          .get();
      expect(userBCart.docs, isEmpty);
    });

    test('addToCart refuses when no authenticated user is present', () {
      // The null-user guard is the client-side half of the authorization
      // boundary: without a UID the cart write must never reach Firestore.
      // (Covered statically because the testing constructor always injects
      // a userId — the production guard is on the null path.)
      final svc = readRepoFile('lib/services/cart_service.dart');
      expect(
        svc,
        contains('if (userId == null || item.id.isEmpty) return false;'),
      );
    });
  });
}
