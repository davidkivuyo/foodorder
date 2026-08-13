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

class PickupDeadlineService {
  PickupDeadlineService._();

  static const int defaultGracePeriodMinutes = 5;

  static DateTime? getNoShowEligibleAt(
    DateTime? pickupDeadline, {
    int gracePeriodMinutes = defaultGracePeriodMinutes,
  }) {
    if (pickupDeadline == null) return null;
    return pickupDeadline.add(Duration(minutes: gracePeriodMinutes));
  }

  static bool isInGracePeriod(
    DateTime? pickupDeadline, {
    int gracePeriodMinutes = defaultGracePeriodMinutes,
  }) {
    if (pickupDeadline == null) return false;
    final now = DateTime.now();
    final eligibleAt = getNoShowEligibleAt(pickupDeadline, gracePeriodMinutes: gracePeriodMinutes)!;
    return !now.isBefore(pickupDeadline) && now.isBefore(eligibleAt);
  }

  static bool isGracePeriodExpired(
    DateTime? pickupDeadline, {
    int gracePeriodMinutes = defaultGracePeriodMinutes,
  }) {
    if (pickupDeadline == null) return false;
    final eligibleAt = getNoShowEligibleAt(pickupDeadline, gracePeriodMinutes: gracePeriodMinutes)!;
    return !DateTime.now().isBefore(eligibleAt);
  }

  static Duration gracePeriodRemainingDuration(
    DateTime? pickupDeadline, {
    int gracePeriodMinutes = defaultGracePeriodMinutes,
  }) {
    if (pickupDeadline == null) return Duration.zero;
    final eligibleAt = getNoShowEligibleAt(pickupDeadline, gracePeriodMinutes: gracePeriodMinutes)!;
    final remaining = eligibleAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static Duration remainingDuration(DateTime? pickupDeadline) {
    if (pickupDeadline == null) return Duration.zero;
    final remaining = pickupDeadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static String formatCountdown(Duration duration) {
    if (duration == Duration.zero) return 'Expired';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }

  static String formatGraceCountdown(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return 'Grace period active · $minutes:$seconds';
  }

  static String formatPickupTime(DateTime? dateTime) {
    if (dateTime == null) return '--';
    final now = DateTime.now();
    final isToday = now.year == dateTime.year &&
        now.month == dateTime.month &&
        now.day == dateTime.day;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    if (isToday) {
      return 'Today $hour:$minute';
    }
    return '${dateTime.day}/${dateTime.month} $hour:$minute';
  }

  static Color countdownColor(Duration remaining) {
    if (remaining == Duration.zero) return Colors.grey;
    final minutes = remaining.inMinutes;
    if (minutes > 10) return Colors.green;
    if (minutes > 5) return Colors.orange;
    return Colors.red;
  }
}
