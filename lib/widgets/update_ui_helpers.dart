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
import 'package:flutter_markdown/flutter_markdown.dart';

/// Shared update-flow UI strings. User-facing copy only — never ABI names,
/// file names, hosts, or JSON.
abstract class UpdateCopy {
  static const String title = 'New version available';
  static const String downloading = 'Downloading update…';
  static const String installing = 'Installing update…';
  static const String completed = 'Update completed.';
  static const String updateNow = 'Update now';
  static const String later = 'Later';
  static const String install = 'Install';
  static const String retry = 'Retry';
  static const String pause = 'Pause';
  static const String resume = 'Resume';
  static const String download = 'Download';
  static const String openSettings = 'Open settings';
}

/// Renders the release notes through a markdown widget (not a raw text dump).
class ReleaseNotesView extends StatelessWidget {
  const ReleaseNotesView({super.key, required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final notes = this.notes.trim();
    if (notes.isEmpty) {
      return const SizedBox.shrink();
    }
    return MarkdownBody(
      data: notes,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: const TextStyle(fontSize: 14, height: 1.4),
      ),
    );
  }
}

/// Formats a duration as a human-friendly "Xm Ys" string.
String formatEta(Duration d) {
  final seconds = d.inSeconds;
  if (seconds <= 0) return '—';
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '${m}m ${s}s';
}

/// Formats a byte count into a short human-readable string.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
