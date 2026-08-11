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
    switch (value) {
      case 'NEW':
        return PickupReliabilityStatus.newUser;
      case 'INSUFFICIENT_HISTORY':
        return PickupReliabilityStatus.insufficientHistory;
      case 'EXCELLENT':
        return PickupReliabilityStatus.excellent;
      case 'GOOD':
        return PickupReliabilityStatus.good;
      case 'NEEDS_IMPROVEMENT':
        return PickupReliabilityStatus.needsImprovement;
      case 'POOR':
        return PickupReliabilityStatus.poor;
      case 'CRITICAL':
        return PickupReliabilityStatus.critical;
      default:
        return PickupReliabilityStatus.newUser;
    }
  }

  String toShortString() {
    switch (this) {
      case PickupReliabilityStatus.newUser:
        return 'NEW';
      case PickupReliabilityStatus.insufficientHistory:
        return 'INSUFFICIENT_HISTORY';
      case PickupReliabilityStatus.excellent:
        return 'EXCELLENT';
      case PickupReliabilityStatus.good:
        return 'GOOD';
      case PickupReliabilityStatus.needsImprovement:
        return 'NEEDS_IMPROVEMENT';
      case PickupReliabilityStatus.poor:
        return 'POOR';
      case PickupReliabilityStatus.critical:
        return 'CRITICAL';
    }
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
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      try {
        return (value as dynamic).toDate() as DateTime;
      } catch (_) {
        return null;
      }
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
    this.updatedAt,
    this.recentPickupHistory = const [],
  });

  /// True when the student has no eligible pickup history yet.
  bool get isNewUser => status == PickupReliabilityStatus.newUser;

  factory PickupReliabilitySummary.fromMap(Map<String, dynamic> map) {
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      try {
        return (value as dynamic).toDate() as DateTime;
      } catch (_) {
        return null;
      }
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
      updatedAt: parseTimestamp(map['updatedAt']),
      recentPickupHistory: history is List
          ? history
                .whereType<Map<String, dynamic>>()
                .map(PickupReliabilityHistoryEntry.fromMap)
                .toList()
          : const [],
    );
  }
}
