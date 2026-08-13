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
import '../models/pickup_reliability.dart';

/// Reusable student-facing Pickup Reliability Card for Phase D.
///
/// Communicates pickup reliability score, status, collection history,
/// and constructive guidance without introducing punitive language or restrictions.
class PickupReliabilityCard extends StatelessWidget {
  final PickupReliabilitySummary? summary;

  const PickupReliabilityCard({
    super.key,
    required this.summary,
  });

  static String getStatusLabel(PickupReliabilityStatus status) {
    return switch (status) {
      PickupReliabilityStatus.newUser => 'New record',
      PickupReliabilityStatus.insufficientHistory => 'Building record',
      PickupReliabilityStatus.excellent => 'Excellent',
      PickupReliabilityStatus.good => 'Good',
      PickupReliabilityStatus.needsImprovement => 'Needs Improvement',
      PickupReliabilityStatus.poor => 'Poor',
      PickupReliabilityStatus.critical => 'Critical',
    };
  }

  static String getStatusMessage(PickupReliabilityStatus status) {
    return switch (status) {
      PickupReliabilityStatus.newUser =>
        'Your pickup record will appear after you complete your first order.',
      PickupReliabilityStatus.insufficientHistory =>
        'Building your pickup record. Keep collecting your orders on time.',
      PickupReliabilityStatus.excellent =>
        'Excellent pickup record. Thank you for collecting your orders on time.',
      PickupReliabilityStatus.good =>
        'Good pickup record. Keep collecting your orders on time.',
      PickupReliabilityStatus.needsImprovement =>
        'Your pickup record needs improvement. Please try to collect your orders within the pickup period.',
      PickupReliabilityStatus.poor =>
        'Please remember to collect your orders during the pickup window to help reduce food waste.',
      PickupReliabilityStatus.critical =>
        'Please make every effort to collect future orders within the pickup period.',
    };
  }

  static Color getStatusColor(PickupReliabilityStatus status) {
    return switch (status) {
      PickupReliabilityStatus.newUser ||
      PickupReliabilityStatus.insufficientHistory =>
        const Color(0xFF1E88E5), // Blue
      PickupReliabilityStatus.excellent => const Color(0xFF2E7D32), // Green
      PickupReliabilityStatus.good => const Color(0xFF43A047), // Light green
      PickupReliabilityStatus.needsImprovement =>
        const Color(0xFFF57C00), // Orange
      PickupReliabilityStatus.poor ||
      PickupReliabilityStatus.critical =>
        const Color(0xFFD32F2F), // Red
    };
  }

  @override
  Widget build(BuildContext context) {
    final rel = summary ?? const PickupReliabilitySummary();
    final status = rel.status;
    final statusLabel = getStatusLabel(status);
    final statusMsg = getStatusMessage(status);
    final statusColor = getStatusColor(status);

    final bool isNewOrInsufficient =
        status == PickupReliabilityStatus.newUser ||
        status == PickupReliabilityStatus.insufficientHistory;

    final scoreDisplay = isNewOrInsufficient
        ? '—'
        : '${rel.reliabilityScore.round()}%';

    // Phase D §10 — recent-window performance (server-maintained fields only;
    // never calculated here). Shown when the student has recent pickup data.
    final bool hasRecentHistory = rel.recentEligibleOrders > 0;
    final String recentSummary = hasRecentHistory
        ? 'Last ${rel.recentEligibleOrders} pickups: '
              '${rel.recentCollectedOrders} collected · '
              '${rel.recentNoShowOrders} missed'
        : '';

    // Phase D §11 — positive reinforcement when recent pickups were collected
    // on time. Informational only; no rewards or account changes.
    final bool recentSuccess =
        !isNewOrInsufficient &&
        hasRecentHistory &&
        rel.recentEligibleOrders >= 3 &&
        rel.recentNoShowOrders == 0;
    final String? encouragement = recentSuccess
        ? 'Great job — you\'ve collected your recent orders on time.'
        : null;

    final semanticText = isNewOrInsufficient
        ? 'Pickup reliability: $statusLabel. $statusMsg'
        : 'Pickup reliability: ${rel.reliabilityScore.round()} percent, $statusLabel. ${rel.collectedOrders} collected, ${rel.noShowOrders} missed. $statusMsg';

    return Semantics(
      label: semanticText,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      size: 20,
                      color: Color(0xFF168039),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Pickup Reliability',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  scoreDisplay,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    letterSpacing: -1,
                  ),
                ),
                if (!isNewOrInsufficient) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${rel.collectedOrders} collected · ${rel.noShowOrders} missed',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (!isNewOrInsufficient) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (rel.reliabilityScore / 100).clamp(0.0, 1.0),
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  minHeight: 6,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              statusMsg,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                height: 1.35,
              ),
            ),
            if (hasRecentHistory) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      recentSummary,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (encouragement != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.emoji_events_outlined,
                      size: 16,
                      color: Color(0xFF2E7D32),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        encouragement,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
