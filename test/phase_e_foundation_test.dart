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

import 'package:flutter_test/flutter_test.dart';
import 'package:campusbite/models/pickup_reliability.dart';

/// Phase E — GRADUATED ORDERING RESTRICTIONS.
///
/// Static guardrail tests (same pattern as the other foundation suites) that
/// assert the shipped Phase E contract survives refactors, complementing the
/// executable emulator coverage in
/// functions/test/phase_e_restriction_integration.test.js:
///   * restrictionLevel/restrictionReason live INSIDE the server-maintained
///     pickupReliability summary (no new collection, no Flutter-side math).
///   * The restriction policy thresholds match AGENTS.md Phase E §3-§6.
///   * Order creation is enforced server-side (placeOrder callable with the
///     transactional active-order limit); the client only pre-checks.
///   * Students (and admins) can never write restriction fields.
void main() {
  String readRepoFile(String path) => File(path).readAsStringSync();

  group('PickupRestrictionLevel model', () {
    test('fromString maps the three levels and fails closed to NORMAL', () {
      expect(
        PickupRestrictionLevel.fromString('NORMAL'),
        PickupRestrictionLevel.normal,
      );
      expect(
        PickupRestrictionLevel.fromString('LIMITED'),
        PickupRestrictionLevel.limited,
      );
      expect(
        PickupRestrictionLevel.fromString('HIGHLY_LIMITED'),
        PickupRestrictionLevel.highlyLimited,
      );
      expect(PickupRestrictionLevel.fromString(null), PickupRestrictionLevel.normal);
      expect(PickupRestrictionLevel.fromString('BANNED'), PickupRestrictionLevel.normal);
      expect(PickupRestrictionLevel.fromString('SUSPENDED'), PickupRestrictionLevel.normal);
    });

    test('toShortString round-trips the server values', () {
      expect(
        PickupRestrictionLevel.limited.toShortString(),
        'LIMITED',
      );
      expect(
        PickupRestrictionLevel.highlyLimited.toShortString(),
        'HIGHLY_LIMITED',
      );
    });

    test('activeOrderLimit: NORMAL→null, LIMITED→2, HIGHLY_LIMITED→1', () {
      const summary = PickupReliabilitySummary();
      expect(summary.activeOrderLimit, isNull);

      const limited = PickupReliabilitySummary(
        restrictionLevel: PickupRestrictionLevel.limited,
      );
      expect(limited.activeOrderLimit, 2);

      const highly = PickupReliabilitySummary(
        restrictionLevel: PickupRestrictionLevel.highlyLimited,
      );
      expect(highly.activeOrderLimit, 1);
    });

    test('fromMap parses restrictionLevel + reason; missing → NORMAL', () {
      final restricted = PickupReliabilitySummary.fromMap({
        'eligibleOrders': 5,
        'reliabilityScore': 40.0,
        'status': 'POOR',
        'restrictionLevel': 'LIMITED',
        'restrictionReason': 'Low pickup reliability',
      });
      expect(restricted.restrictionLevel, PickupRestrictionLevel.limited);
      expect(restricted.restrictionReason, 'Low pickup reliability');
      expect(restricted.activeOrderLimit, 2);

      final legacy = PickupReliabilitySummary.fromMap({
        'eligibleOrders': 3,
        'reliabilityScore': 20.0,
        'status': 'CRITICAL',
      });
      expect(legacy.restrictionLevel, PickupRestrictionLevel.normal);
      expect(legacy.restrictionReason, isNull);
      expect(legacy.activeOrderLimit, isNull);
    });
  });

  group('Backend — restriction engine (server-authoritative)', () {
    late String functionsSrc;
    setUpAll(() {
      functionsSrc = readRepoFile('functions/index.js');
    });

    test('restrictionFor derives levels from the reliability summary only', () {
      final restrictionFn = functionsSrc.substring(
        functionsSrc.indexOf('function restrictionFor('),
        functionsSrc.indexOf('function recomputeReliability('),
      );
      // Policy thresholds (§3, §4-§6).
      expect(restrictionFn, contains('eligibleOrders < 3'));
      expect(restrictionFn, contains('score >= 50'));
      expect(restrictionFn, contains('score >= 25'));
      expect(restrictionFn, contains('activeOrderLimit'));
      // Levels are NORMAL / LIMITED / HIGHLY_LIMITED — the new restriction
      // system deliberately has no STRIKE / BANNED / SUSPENDED states (§9).
      expect(restrictionFn, contains('RESTRICTION_LEVEL_NORMAL'));
      expect(restrictionFn, contains('RESTRICTION_LEVEL_LIMITED'));
      expect(restrictionFn, contains('RESTRICTION_LEVEL_HIGHLY_LIMITED'));
      expect(restrictionFn, isNot(contains('STRIKE')));
      expect(restrictionFn, isNot(contains('BANNED')));
      expect(restrictionFn, isNot(contains('SUSPENDED')));
    });

    test('active-order statuses exclude terminal states (§10)', () {
      const active = [
        'pending', 'accepted', 'preparing', 'ready',
      ];
      expect(
        functionsSrc,
        contains('ACTIVE_ORDER_STATUSES = ["pending", "accepted", "preparing", "ready"]'),
      );
      expect(active, isNot(contains('cancelled')));
      expect(active, isNot(contains('collected')));
      expect(active, isNot(contains('no_show')));
      expect(active, isNot(contains('rejected')));
    });

    test('every reliability summary carries restrictionLevel/restrictionReason', () {
      // Both the empty (new-user) summary and the recomputed summary embed
      // the derived restriction state — no separate collection, no extra
      // writes (§7, §29).
      expect(functionsSrc, contains('restrictionLevel: RESTRICTION_LEVEL_NORMAL'));
      expect(functionsSrc, contains('restrictionLevel: restriction.restrictionLevel'));
      expect(functionsSrc, contains('restrictionReason: restriction.restrictionReason'));
    });

    test('placeOrder callable enforces the limit transactionally (§12-§14)', () {
      final callableSection = functionsSrc.substring(
        functionsSrc.indexOf('FUNCTION: placeOrder'),
        functionsSrc.indexOf('// ── Order foodIds backfill'),
      );
      expect(callableSection, contains('transaction.get('));
      expect(callableSection, contains('.where("status", "in", ACTIVE_ORDER_STATUSES)'));
      expect(callableSection, contains('activeSnapshot.size >= limit'));
      expect(callableSection, contains('code: "ACTIVE_ORDER_LIMIT"'));
      // Concurrency: the contention write serialises concurrent attempts.
      expect(callableSection, contains('transaction.update(ctx.userRef,'));
      // Fail-safe (§18): never assume 0 active orders when verification fails.
      expect(callableSection, contains('Unable to verify your active orders'));
    });
  });

  group('Firestore rules — restriction fields are read-only (§26, §37)', () {
    late String rules;
    setUpAll(() {
      rules = readRepoFile('firestore.rules');
    });

    test('pickupReliability (incl. restrictionLevel) is blocked for students', () {
      final studentFn = rules.substring(
        rules.indexOf('function studentNotModifyingProtectedFields()'),
        rules.indexOf('function validUserCreateRequest()'),
      );
      expect(studentFn, contains("!('pickupReliability' in changed)"));
      expect(studentFn, contains('hasOnly(allowed)'));
    });

    test('admins cannot modify restriction fields via validAdminStrikeUpdate', () {
      final adminFn = rules.substring(
        rules.indexOf('function validAdminStrikeUpdate()'),
        rules.indexOf('// ── Review validation'),
      );
      expect(adminFn, isNot(contains('pickupReliability')));
      expect(adminFn, contains("'strikeCount', 'strikePercentage', 'accountStatus'"));
    });
  });

  group('Firestore indexes — active-order query', () {
    test('composite index exists for studentId + status', () {
      final indexes = readRepoFile('firestore.indexes.json');
      // Two-field index (and/or the three-field one whose prefix covers it).
      expect(
        indexes,
        contains('"fieldPath": "studentId", "order": "ASCENDING"'),
      );
      expect(
        indexes,
        contains('"fieldPath": "status", "order": "ASCENDING"'),
      );
    });
  });

  group('Client — checkout pre-check and messaging (§16, §17, §34)', () {
    test('CartService routes order creation through the placeOrder callable', () {
      final cart = readRepoFile('lib/services/cart_service.dart');
      expect(cart, contains('OrderPlacementService'));
      expect(cart, contains('_orderPlacement.placeOrder(payload)'));
      expect(cart, contains('_checkActiveOrderLimit'));
      expect(cart, contains('OrderStatus.activeOrderStatuses'));
    });

    test('OrderPlacementService maps the limit rejection to a stable failure', () {
      final service = readRepoFile('lib/services/order_placement_service.dart');
      expect(service, contains('OrderPlacementFailure.activeOrderLimit'));
      expect(service, contains('ACTIVE_ORDER_LIMIT'));
      expect(service, contains('OrderPlacementFailure.unableToVerify'));
      expect(service, contains('OrderPlacementFailure.unavailableFood'));
    });

    test('My Profile shows the §16 non-punitive restriction messaging ',
        () {
      final notice = readRepoFile('lib/widgets/restriction_notice.dart');
      // Phase F §15 — recovery framing: positive, forward-looking, never
      // punitive.
      expect(
        notice,
        contains('Your pickup reliability is improving.'),
      );
      expect(
        notice,
        contains('you can now have up to'),
      );
      // The detail string is split across adjacent Dart literals, so
      // assert the raw fragments rather than the compiled concatenation.
      expect(
        notice,
        contains('active order at a time'),
      );
      expect(
        notice,
        contains('your limit will relax'),
      );
      expect(notice, isNot(contains('Strike')));
      expect(notice, isNot(contains('Ban')));
      expect(notice, isNot(contains('Suspend')));
      expect(notice, isNot(contains('needs improvement')));
      expect(notice, isNot(contains('punish')));
    });

    test('the Phase E emulator integration suite is runnable', () {
      final integration =
          readRepoFile('functions/test/phase_e_restriction_integration.test.js');
      expect(integration, contains('initializeTestEnvironment'));
      expect(integration, contains('placeOrder.run'));
      expect(integration, contains('ACTIVE_ORDER_LIMIT'));
    });
  });
}
