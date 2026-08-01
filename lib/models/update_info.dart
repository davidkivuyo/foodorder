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

/// Parsed update metadata served by `https://dl.larason.space/latest` (or
/// `/release/{tag}`).
///
/// Unknown/future top-level fields are kept intact in [raw] so a newer server
/// can add fields (e.g. `channel`, `rolloutPercentage`) without breaking this
/// client. Only fields this client understands are parsed out.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.minimumVersion,
    required this.forceUpdate,
    required this.releaseNotes,
    required this.downloads,
    required this.checksums,
    required this.stale,
    this.raw = const {},
  });

  /// Target release version, e.g. `1.4.2`.
  final String version;

  /// Lowest version the app must be at or above to keep working.
  final String minimumVersion;

  /// When true the update must be installed before the app can be used.
  final bool forceUpdate;

  /// User-facing markdown release notes.
  final String releaseNotes;

  /// Download URLs keyed by ABI (`universal`, `arm64-v8a`, ...).
  final Map<String, String> downloads;

  /// Checksum file URLs keyed by the same ABI keys.
  final Map<String, String> checksums;

  /// True when the response came from a stale edge cache (GitHub was
  /// unreachable on the Worker). Not a reason to error — proceed as normal.
  final bool stale;

  /// The full parsed JSON, including unknown/future fields, untouched.
  final Map<String, dynamic> raw;

  bool get hasDownloads => downloads.isNotEmpty;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String? ?? '',
      minimumVersion: json['minimumVersion'] as String? ?? '',
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      releaseNotes: json['releaseNotes'] as String? ?? '',
      downloads: _toStringMap(json['downloads']),
      checksums: _toStringMap(json['checksums']),
      stale: json['stale'] as bool? ?? false,
      raw: json,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ...raw,
      'version': version,
      'minimumVersion': minimumVersion,
      'forceUpdate': forceUpdate,
      'releaseNotes': releaseNotes,
      'downloads': downloads,
      'checksums': checksums,
      'stale': stale,
    };
  }

  static Map<String, String> _toStringMap(Object? value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return const {};
  }
}

/// Compares dotted numeric version strings (e.g. `1.4.2`, `1.10.0+3`).
///
/// Returns `1` when [a] is newer than [b], `-1` when older, `0` when equal.
/// Non-numeric suffixes and build numbers are tolerated.
int compareVersions(String a, String b) {
  final aParts = _numericParts(a);
  final bParts = _numericParts(b);
  final len = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < len; i++) {
    final av = i < aParts.length ? aParts[i] : 0;
    final bv = i < bParts.length ? bParts[i] : 0;
    if (av != bv) return av > bv ? 1 : -1;
  }
  return 0;
}

List<int> _numericParts(String version) {
  final core = version.split('+').first.trim();
  return core
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList(growable: false);
}
