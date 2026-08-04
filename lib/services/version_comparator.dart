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

import 'package:pub_semver/pub_semver.dart';

/// Thrown when a version string cannot be parsed as valid semver.
///
/// Callers must treat a [VersionParseException] as fail-safe-neutral — the
/// same way an update-check network failure is handled (continue on the
/// current version, debug-log only, never crash or block the user).
class VersionParseException implements Exception {
  VersionParseException(this.input);

  /// The raw string that could not be parsed.
  final String input;

  @override
  String toString() => 'VersionParseException: "$input" is not valid semver';
}

/// Single source of truth for semver-aware version comparison in the update
/// system.
///
/// Implements the semver precedence rules delegated to `package:pub_semver`:
/// numeric core comparison, pre-release identifier comparison, numeric-vs-
/// alphanumeric identifier rules, and bare-release-beats-prerelease.
///
/// This module knows nothing about channels, force-update flags, or UI state —
/// it only decides whether one version is newer than another.
class VersionComparator {
  VersionComparator._();

  /// Returns true when [remote] is a newer release than [local].
  ///
  /// Throws [VersionParseException] on malformed input — it never falls back
  /// to string comparison and never silently reports "no update".
  static bool isNewer({required String local, required String remote}) {
    return _parse(remote).compareTo(_parse(local)) > 0;
  }

  /// Returns true when [local] is strictly below [minimum].
  ///
  /// Throws [VersionParseException] on malformed input.
  static bool isBelowMinimum({
    required String local,
    required String minimum,
  }) {
    return _parse(local).compareTo(_parse(minimum)) < 0;
  }

  /// Parses [input] as semver, stripping a leading `v`/`V` (release tags are
  /// `v1.0.0-dev`) and surrounding whitespace before delegating to
  /// `package:pub_semver`. Any parse failure surfaces as [VersionParseException].
  ///
  /// The complete input is validated by `pub_semver` first, then the returned
  /// [Version] is a copy with the `+build` metadata dropped, so build suffixes
  /// are precedence-neutral per the semver spec (pub_semver's `compareTo`
  /// otherwise uses build as a final tiebreaker).
  static Version _parse(String input) {
    var cleaned = input.trim();
    if (cleaned.isNotEmpty && (cleaned[0] == 'v' || cleaned[0] == 'V')) {
      cleaned = cleaned.substring(1);
    }
    try {
      final parsed = Version.parse(cleaned);
      return Version(
        parsed.major,
        parsed.minor,
        parsed.patch,
        pre: parsed.preRelease.isEmpty ? null : parsed.preRelease.join('.'),
      );
    } on FormatException {
      throw VersionParseException(input);
    }
  }
}
