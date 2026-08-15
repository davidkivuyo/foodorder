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

/// Phase D §12 — non-punitive no-show explanation shown in the order details
/// sheet. Mirrors the ORDER_NO_SHOW notification the student received; the
/// wording is informational and never threatening.
///
/// Phase G — when [excused] is true (an administrator excused the missed
/// pickup), the notice explains that the order itself was not collected but
/// is excluded from the student's pickup reliability calculation. No admin
/// UID or private note is ever exposed.
class NoShowNotice extends StatelessWidget {
  final bool excused;

  const NoShowNotice({super.key, this.excused = false});

  @override
  Widget build(BuildContext context) {
    final Color accent = excused ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final Color bg = excused ? Colors.green.shade50 : Colors.red.shade50;
    final Color border = excused ? Colors.green.shade200 : Colors.red.shade200;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            excused ? Icons.verified_outlined : Icons.cancel_outlined,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  excused ? 'No-show excused' : 'No-show recorded',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: excused ? Colors.green.shade900 : Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  excused
                      ? 'An administrator reviewed this order and excused '
                          'the missed pickup. It will not affect your pickup '
                          'reliability.'
                      : 'The pickup window and grace period ended before the order '
                          'was collected. An "Order Missed" notification was sent '
                          'to you.',
                  style: TextStyle(
                    fontSize: 12,
                    color: excused ? Colors.green.shade800 : Colors.red.shade800,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
