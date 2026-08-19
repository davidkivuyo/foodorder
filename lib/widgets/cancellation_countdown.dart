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

/// Local countdown for the 2-minute order cancellation window.
///
/// Pure UI: ticks once per second, derives the remaining time from the
/// server-authoritative [cancellationDeadline] stored in Firestore and never
/// writes to Firestore itself. When the remaining time reaches zero the
/// [onExpired] callback fires so the parent can hide the cancel action.
class CancellationCountdown extends StatefulWidget {
  final DateTime? cancellationDeadline;
  final ValueChanged<Duration>? onTick;
  final VoidCallback? onExpired;

  const CancellationCountdown({
    super.key,
    required this.cancellationDeadline,
    this.onTick,
    this.onExpired,
  });

  @override
  State<CancellationCountdown> createState() => _CancellationCountdownState();
}

class _CancellationCountdownState extends State<CancellationCountdown> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _expiredNotified = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _startTimer();
  }

  @override
  void didUpdateWidget(CancellationCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cancellationDeadline != widget.cancellationDeadline) {
      _expiredNotified = false;
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed) return;
      _updateRemaining();
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    _startTimer();
  }

  void _updateRemaining() {
    final deadline = widget.cancellationDeadline;
    final remaining = deadline == null
        ? Duration.zero
        : deadline.difference(DateTime.now());
    final clamped = remaining.isNegative ? Duration.zero : remaining;
    if (clamped != _remaining) {
      setState(() => _remaining = clamped);
    }
    widget.onTick?.call(clamped);
    if (clamped == Duration.zero && !_expiredNotified) {
      _expiredNotified = true;
      // Defer to after the current frame: initState can mount with an
      // already-expired deadline, and invoking the callback synchronously
      // there would call the parent's setState during its own build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) widget.onExpired?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cancellationDeadline == null) {
      return const SizedBox.shrink();
    }

    final text = _format(_remaining);
    final color = _remaining <= const Duration(seconds: 30)
        ? Colors.red.shade700
        : Colors.red.shade400;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$minutes:$seconds';
  }
}
