import 'package:flutter/material.dart';

class PickupDeadlineService {
  PickupDeadlineService._();

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
