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

import 'package:cloud_firestore/cloud_firestore.dart';

/// Phase B.2 — pickup reliability status classification.
/// Informational only; no restrictions are attached to any status.
enum PickupReliabilityStatus {
  newUser,
  insufficientHistory,
  excellent,
  good,
  needsImprovement,
  poor,
  critical;

  static PickupReliabilityStatus fromString(String value) {
    return switch (value) {
      'NEW' => PickupReliabilityStatus.newUser,
      'INSUFFICIENT_HISTORY' => PickupReliabilityStatus.insufficientHistory,
      'EXCELLENT' => PickupReliabilityStatus.excellent,
      'GOOD' => PickupReliabilityStatus.good,
      'NEEDS_IMPROVEMENT' => PickupReliabilityStatus.needsImprovement,
      'POOR' => PickupReliabilityStatus.poor,
      'CRITICAL' => PickupReliabilityStatus.critical,
      _ => PickupReliabilityStatus.newUser,
    };
  }

  String toShortString() {
    return switch (this) {
      PickupReliabilityStatus.newUser => 'NEW',
      PickupReliabilityStatus.insufficientHistory => 'INSUFFICIENT_HISTORY',
      PickupReliabilityStatus.excellent => 'EXCELLENT',
      PickupReliabilityStatus.good => 'GOOD',
      PickupReliabilityStatus.needsImprovement => 'NEEDS_IMPROVEMENT',
      PickupReliabilityStatus.poor => 'POOR',
      PickupReliabilityStatus.critical => 'CRITICAL',
    };
  }
}

/// Phase E — graduated ordering restriction level (server-authoritative).
///
/// Derived from the reliability summary by the backend restriction engine;
/// students and admins may read it but never write it. There is deliberately
/// no BANNED / SUSPENDED / STRIKE state in this system.
enum PickupRestrictionLevel {
  normal,
  limited,
  highlyLimited;

  static PickupRestrictionLevel fromString(String? value) {
    return switch (value) {
      'LIMITED' => PickupRestrictionLevel.limited,
      'HIGHLY_LIMITED' => PickupRestrictionLevel.highlyLimited,
      _ => PickupRestrictionLevel.normal,
    };
  }

  String toShortString() {
    return switch (this) {
      PickupRestrictionLevel.normal => 'NORMAL',
      PickupRestrictionLevel.limited => 'LIMITED',
      PickupRestrictionLevel.highlyLimited => 'HIGHLY_LIMITED',
    };
  }
}

/// One entry in the server-maintained recent pickup history window.
class PickupReliabilityHistoryEntry {
  final String orderId;
  final String outcome; // 'COLLECTED' | 'NO_SHOW'
  final DateTime? timestamp;

  const PickupReliabilityHistoryEntry({
    required this.orderId,
    required this.outcome,
    this.timestamp,
  });

  factory PickupReliabilityHistoryEntry.fromMap(Map<String, dynamic> map) {
    // Explicit type checks only — never a bare catch (which would also
    // swallow Error subtypes and mask defects). Firestore timestamps arrive
    // as Timestamp objects; anything else is not a valid timestamp.
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is Timestamp) return value.toDate();
      return null;
    }

    return PickupReliabilityHistoryEntry(
      orderId: map['orderId'] as String? ?? '',
      outcome: map['outcome'] as String? ?? '',
      timestamp: parseTimestamp(map['timestamp']),
    );
  }
}

/// Server-authoritative pickup reliability summary stored in the nested
/// `pickupReliability` map of `users/{uid}`.
///
/// The student may READ their own summary but never WRITE it: the backend
/// reliability engine is the only writer. A missing summary (new user)
/// parses to a neutral NEW state — never 0%.
class PickupReliabilitySummary {
  final int eligibleOrders;
  final int collectedOrders;
  final int noShowOrders;
  final double collectionRate;
  final int recentEligibleOrders;
  final int recentCollectedOrders;
  final int recentNoShowOrders;
  final double recentCollectionRate;
  final double reliabilityScore;
  final PickupReliabilityStatus status;

  // Phase E — graduated ordering restriction (server-authoritative; derived
  // from this summary by the backend restriction engine). A missing value
  // (legacy summary) parses to NORMAL — never a restriction.
  final PickupRestrictionLevel restrictionLevel;
  final String? restrictionReason;

  final DateTime? updatedAt;
  final List<PickupReliabilityHistoryEntry> recentPickupHistory;

  const PickupReliabilitySummary({
    this.eligibleOrders = 0,
    this.collectedOrders = 0,
    this.noShowOrders = 0,
    this.collectionRate = 100,
    this.recentEligibleOrders = 0,
    this.recentCollectedOrders = 0,
    this.recentNoShowOrders = 0,
    this.recentCollectionRate = 100,
    this.reliabilityScore = 100,
    this.status = PickupReliabilityStatus.newUser,
    this.restrictionLevel = PickupRestrictionLevel.normal,
    this.restrictionReason,
    this.updatedAt,
    this.recentPickupHistory = const <PickupReliabilityHistoryEntry>[],
  });

  /// Whether the student is currently restricted to a finite active-order
  /// limit (Phase E). Null when unrestricted (NORMAL).
  int? get activeOrderLimit => switch (restrictionLevel) {
        PickupRestrictionLevel.normal => null,
        PickupRestrictionLevel.limited => 2,
        PickupRestrictionLevel.highlyLimited => 1,
      };

  /// True when the student has no eligible pickup history yet.
  bool get isNewUser => status == PickupReliabilityStatus.newUser;

  factory PickupReliabilitySummary.fromMap(Map<String, dynamic> map) {
    // Explicit type checks only — never a bare catch (which would also
    // swallow Error subtypes and mask defects). Firestore timestamps arrive
    // as Timestamp objects; anything else is not a valid timestamp.
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is Timestamp) return value.toDate();
      return null;
    }

    final history = map['recentPickupHistory'];
    return PickupReliabilitySummary(
      eligibleOrders: (map['eligibleOrders'] as num?)?.toInt() ?? 0,
      collectedOrders: (map['collectedOrders'] as num?)?.toInt() ?? 0,
      noShowOrders: (map['noShowOrders'] as num?)?.toInt() ?? 0,
      collectionRate: (map['collectionRate'] as num?)?.toDouble() ?? 100,
      recentEligibleOrders: (map['recentEligibleOrders'] as num?)?.toInt() ?? 0,
      recentCollectedOrders:
          (map['recentCollectedOrders'] as num?)?.toInt() ?? 0,
      recentNoShowOrders: (map['recentNoShowOrders'] as num?)?.toInt() ?? 0,
      recentCollectionRate:
          (map['recentCollectionRate'] as num?)?.toDouble() ?? 100,
      reliabilityScore: (map['reliabilityScore'] as num?)?.toDouble() ?? 100,
      status: PickupReliabilityStatus.fromString(
        map['status'] as String? ?? 'NEW',
      ),
      restrictionLevel: PickupRestrictionLevel.fromString(
        map['restrictionLevel'] as String?,
      ),
      restrictionReason: map['restrictionReason'] as String?,
      updatedAt: parseTimestamp(map['updatedAt']),
      // Normalise each entry with Map<String, dynamic>.from() rather than a
      // strict whereType<Map<String, dynamic>>() filter: Firestore-returned
      // maps can carry a different runtime generic instantiation, and the
      // strict check would silently drop valid entries. Non-Map entries are
      // still skipped (fail closed for malformed data).
      recentPickupHistory: history is List
          ? history
                .whereType<Map>()
                .map((e) => PickupReliabilityHistoryEntry.fromMap(
                      Map<String, dynamic>.from(e),
                    ))
                .toList()
          : const <PickupReliabilityHistoryEntry>[],
    );
  }
}
