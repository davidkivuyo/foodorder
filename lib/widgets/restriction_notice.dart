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

/// Phase E §16 — user-friendly ordering-limit notice shown on the profile
/// when the student's restriction level is not NORMAL.
///
/// Non-punitive wording (§34) and an explicit semantics label so the
/// restriction is never communicated by colour alone (§35).
class RestrictionNotice extends StatelessWidget {
  final PickupRestrictionLevel level;

  /// The student's current active-order limit (null when unrestricted).
  final int? activeOrderLimit;

  const RestrictionNotice({
    super.key,
    required this.level,
    this.activeOrderLimit,
  });

  /// User-facing headline for a restriction level (§16, Phase F §15).
  ///
  /// Phase F recovery framing: restrictions relax automatically as the
  /// student collects orders, so the wording stays positive and points at
  /// the recovery path — never at strikes, bans or penalties.
  static String? headlineFor(PickupRestrictionLevel level) {
    return switch (level) {
      PickupRestrictionLevel.normal => null,
      PickupRestrictionLevel.limited => 'Your pickup reliability is improving.',
      PickupRestrictionLevel.highlyLimited =>
        'Your pickup reliability is improving.',
    };
  }

  /// User-facing ordering-limit line for a restriction level (§16,
  /// Phase F §15). Reflects the current limit and the automatic recovery
  /// path.
  static String? detailFor(PickupRestrictionLevel level, int? limit) {
    return switch (level) {
      PickupRestrictionLevel.normal => null,
      PickupRestrictionLevel.limited =>
        'Keep collecting your orders on time — you can now have up to '
        '${limit ?? 2} active orders at a time.',
      PickupRestrictionLevel.highlyLimited =>
        'Keep collecting your orders on time — your ordering limit will '
        'relax as your pickup reliability improves.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final headline = headlineFor(level);
    if (headline == null) return const SizedBox.shrink();
    final detail = detailFor(level, activeOrderLimit);
    final text = detail == null ? headline : '$headline $detail';

    return Semantics(
      label: 'Ordering limit. $text',
      container: true,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF9A825)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 20, color: Color(0xFFF57F17)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF795548),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
