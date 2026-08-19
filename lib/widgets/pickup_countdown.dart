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

    final inGrace = PickupDeadlineService.isInGracePeriod(widget.pickupDeadline);
    final graceExpired = PickupDeadlineService.isGracePeriodExpired(widget.pickupDeadline);
    final graceRemaining = PickupDeadlineService.gracePeriodRemainingDuration(widget.pickupDeadline);

    final color = PickupDeadlineService.countdownColor(_remaining);
    final text = PickupDeadlineService.formatCountdown(_remaining);

    final String label;
    final Color labelColor;

    switch (widget.deadlineStatus) {
      case DeadlineStatus.collected:
        label = 'Collected';
        labelColor = Colors.grey;
        break;
      case DeadlineStatus.expired:
        label = 'No-show recorded';
        labelColor = Colors.grey;
        break;
      case DeadlineStatus.active:
        if (graceExpired) {
          label = 'Pickup window expired';
          labelColor = Colors.grey;
        } else if (inGrace) {
          label = PickupDeadlineService.formatGraceCountdown(graceRemaining);
          labelColor = Colors.orange;
        } else {
          label = text;
          labelColor = color;
        }
        break;
      case DeadlineStatus.notReady:
        label = '';
        labelColor = Colors.grey;
        break;
    }

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
