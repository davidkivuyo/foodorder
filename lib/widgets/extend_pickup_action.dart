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
import '../services/pickup_extension_service.dart';

/// The one-tap "extend pickup" action shown on ready orders, plus the
/// confirmation chip once the extension has been used.
///
/// Shared by the order card and the order details bottom sheet.
///
/// Self-expiring: runs a 1-second timer and hides the action as soon as the
/// pickup deadline passes. Eligibility is a time check
/// (`deadline.isAfter(now)`) that the parent card only evaluates at build
/// time, and nothing rebuilds the card when the deadline itself passes (the
/// order document does not change until the no-show processor flips the
/// status at the end of the grace period). Without the local timer the button
/// would stay visible during the grace period and produce a confusing
/// rejection when tapped. The grace-period state itself is communicated by
/// [PickupCountdown]'s chip, so hiding the action here is enough.
class ExtendPickupAction extends StatefulWidget {
  final bool canExtend;
  final bool extended;
  final bool isExtending;
  final DateTime? pickupDeadline;
  final VoidCallback onExtend;

  /// Test seam: source of "now" for the expiry check. Defaults to
  /// [DateTime.now]; widget tests inject a controllable clock so the
  /// deadline-elapses-while-mounted path is deterministic.
  final DateTime Function() clock;

  const ExtendPickupAction({
    super.key,
    required this.canExtend,
    required this.extended,
    required this.isExtending,
    required this.pickupDeadline,
    required this.onExtend,
    this.clock = DateTime.now,
  });

  @override
  State<ExtendPickupAction> createState() => _ExtendPickupActionState();
}

class _ExtendPickupActionState extends State<ExtendPickupAction> {
  Timer? _timer;
  bool _deadlinePassed = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _checkDeadline();
    _startTimer();
  }

  @override
  void didUpdateWidget(ExtendPickupAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickupDeadline != widget.pickupDeadline) {
      // A new (e.g. extended) deadline may make the action available again.
      _deadlinePassed = false;
      _checkDeadline();
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
    if (_deadlinePassed) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed) return;
      _checkDeadline();
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    if (_deadlinePassed) return;
    _startTimer();
  }

  void _checkDeadline() {
    final deadline = widget.pickupDeadline;
    if (deadline == null) return;
    if (!deadline.isAfter(widget.clock())) {
      if (!_deadlinePassed) {
        setState(() => _deadlinePassed = true);
      }
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Once the deadline has passed (even if the parent has not rebuilt yet)
    // the action is hidden — the grace-period chip communicates the state.
    final canExtend = widget.canExtend && !_deadlinePassed;

    if (canExtend) {
      return OutlinedButton.icon(
        onPressed: widget.isExtending ? null : widget.onExtend,
        icon: widget.isExtending
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.timer_outlined, size: 16),
        label: Text(
          widget.isExtending
              ? 'Extending…'
              : 'Extend pickup by ${PickupExtensionService.extensionMinutes} min',
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.orange.shade900,
          side: BorderSide(color: Colors.orange.shade400),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
    }
    if (widget.extended) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 14,
            color: Colors.green.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            'Pickup extended by ${PickupExtensionService.extensionMinutes} min',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.green.shade700,
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
