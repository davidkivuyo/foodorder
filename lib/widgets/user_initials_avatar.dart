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

/// Returns uppercase initials from a full name.
/// Single name  → first letter only (example "lembotor" → "L")
/// Multiple names → first letter of each of the first two words (example "Lembotor larabal" → "LL")
String initialsFromName(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// Deterministically picks one of several curated colours based on the name.
/// The same name always produces the same colour.
Color avatarColorFromName(String name) {
  const List<Color> palette = [
    Color(0xFFE53935), // red
    Color(0xFF8E24AA), // purple
    Color(0xFF1E88E5), // blue
    Color(0xFF00897B), // teal
    Color(0xFF43A047), // green
    Color(0xFFF4511E), // deep orange
    Color(0xFF6D4C41), // brown
    Color(0xFF3949AB), // indigo
    Color(0xFF00ACC1), // cyan
    Color(0xFFFF8F00), // amber
  ];
  if (name.isEmpty) return palette[0];
  final index = name.codeUnits.fold(0, (acc, c) => acc + c) % palette.length;
  Color base = palette[index];
  if (base.computeLuminance() > 0.5) {
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0)).toColor();
  }
  return base;
}

/// Shared styled avatar component displaying user initials and dynamic deterministic colour.
class UserInitialsAvatar extends StatelessWidget {
  final String initials;
  final Color color;
  final double size;

  const UserInitialsAvatar({
    super.key,
    required this.initials,
    required this.color,
    this.size = 70,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = size * 0.37;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.34),
        border: Border.all(
          color: HSLColor.fromColor(color)
              .withLightness(
                (HSLColor.fromColor(color).lightness - 0.20).clamp(0.0, 1.0),
              )
              .toColor(),
          width: 3,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
