import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/order.dart';
import '../services/pickup_deadline_service.dart';

class PickupCountdown extends StatefulWidget {
  final DateTime? pickupDeadline;
  final DeadlineStatus deadlineStatus;

  const PickupCountdown({
    super.key,
    required this.pickupDeadline,
    required this.deadlineStatus,
  });

  @override
  State<PickupCountdown> createState() => _PickupCountdownState();
}

class _PickupCountdownState extends State<PickupCountdown> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _startTimer();
  }

  @override
  void didUpdateWidget(PickupCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickupDeadline != widget.pickupDeadline ||
        oldWidget.deadlineStatus != widget.deadlineStatus) {
      _updateRemaining();
      _resetTimer();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    if (_shouldStop()) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed) return;
      _updateRemaining();
      if (_shouldStop()) {
        _timer?.cancel();
      }
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    if (_shouldStop()) return;
    _startTimer();
  }

  bool _shouldStop() {
    return widget.deadlineStatus == DeadlineStatus.collected ||
        widget.deadlineStatus == DeadlineStatus.expired;
  }

  void _updateRemaining() {
    setState(() {
      _remaining = PickupDeadlineService.remainingDuration(
        widget.pickupDeadline,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deadlineStatus == DeadlineStatus.notReady ||
        widget.pickupDeadline == null) {
      return const SizedBox.shrink();
    }

    final color = PickupDeadlineService.countdownColor(_remaining);
    final text = PickupDeadlineService.formatCountdown(_remaining);

    final label = switch (widget.deadlineStatus) {
      DeadlineStatus.collected => 'Collected',
      DeadlineStatus.expired => 'Expired',
      DeadlineStatus.active => text,
      DeadlineStatus.notReady => '',
    };

    final labelColor = switch (widget.deadlineStatus) {
      DeadlineStatus.collected => Colors.grey,
      DeadlineStatus.expired => Colors.grey,
      DeadlineStatus.active => color,
      DeadlineStatus.notReady => Colors.grey,
    };

    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: labelColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: labelColor.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
      ),
    );
  }
}
