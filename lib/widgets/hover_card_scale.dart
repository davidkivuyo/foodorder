import 'package:flutter/material.dart';

class HoverCardScale extends StatefulWidget {
  final Widget child;
  const HoverCardScale({super.key, required this.child});

  @override
  State<HoverCardScale> createState() => _HoverCardScaleState();
}

class _HoverCardScaleState extends State<HoverCardScale> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 850;

    // Disable animation on mobile/tablets to save battery and avoid touch layout shift issues
    if (!isDesktop) return widget.child;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..translate(0.0, _isHovered ? -6.0 : 0.0),
        child: AnimatedScale(
          scale: _isHovered ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}
