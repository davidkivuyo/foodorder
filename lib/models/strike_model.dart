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

/// Allowed strike percentage values.
class StrikePercentage {
  static const int none = 0;
  static const int warning = 50;
  static const int suspended = 100;

  /// Returns true only if [value] is one of the allowed strike percentages.
  static bool isValid(int value) {
    return value == none || value == warning || value == suspended;
  }
}

/// The stored account status derived from [StrikePercentage].
enum AccountStatus {
  active,
  suspended;

  String get value {
    switch (this) {
      case AccountStatus.active:
        return 'ACTIVE';
      case AccountStatus.suspended:
        return 'SUSPENDED';
    }
  }

  static AccountStatus fromString(String status) {
    switch (status) {
      case 'ACTIVE':
        return AccountStatus.active;
      case 'SUSPENDED':
        return AccountStatus.suspended;
      default:
        throw ArgumentError.value(
          status,
          'status',
          'Unknown AccountStatus value. Must be one of: ACTIVE, SUSPENDED',
        );
    }
  }
}

/// Display-level state that determines the UI appearance.
enum StrikeDisplayStatus {
  active,
  warning,
  suspended;

  String get label {
    switch (this) {
      case StrikeDisplayStatus.active:
        return 'Active';
      case StrikeDisplayStatus.warning:
        return 'Warning';
      case StrikeDisplayStatus.suspended:
        return 'Suspended';
    }
  }

  String get emoji {
    switch (this) {
      case StrikeDisplayStatus.active:
        return '🟢';
      case StrikeDisplayStatus.warning:
        return '🟠';
      case StrikeDisplayStatus.suspended:
        return '🔴';
    }
  }
}

/// Derive the display-level status from a strike percentage.
StrikeDisplayStatus displayStatusFromPercentage(int percentage) {
  if (percentage >= StrikePercentage.suspended) {
    return StrikeDisplayStatus.suspended;
  } else if (percentage >= StrikePercentage.warning) {
    return StrikeDisplayStatus.warning;
  }
  return StrikeDisplayStatus.active;
}

/// Compute the [AccountStatus] field value from a strike percentage.
AccountStatus accountStatusFromPercentage(int percentage) {
  if (percentage >= StrikePercentage.suspended) {
    return AccountStatus.suspended;
  }
  return AccountStatus.active;
}
