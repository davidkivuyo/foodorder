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

import 'package:geolocator/geolocator.dart';

/// Business logic for distance-based pickup window calculation.
///
/// Responsibilities:
/// - Calculate walking distance between two coordinates
/// - Convert distance to a pickup window in minutes
///
/// No UI code, no Firestore reads. Pure calculation service.
class PickupWindowService {
  PickupWindowService._();

  /// Calculate distance in metres between two geographic coordinates using
  /// the device's built-in GPS calculation (Geolocator.distanceBetween).
  ///
  /// Returns the straight-line distance in metres.
  static double calculateDistance({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  /// Convert a distance in metres to a pickup window in minutes.
  ///
  /// Rules:
  ///   0 – 250 metres     → 10 minutes
  ///   250 – 600 metres   → 15 minutes
  ///   600 – 1200 metres  → 20 minutes
  ///   Above 1200 metres  → 25 minutes
  ///
  /// Returns an integer between 10 and 25.
  static int calculatePickupWindow(double distanceMeters) {
    if (distanceMeters <= 250) return 10;
    if (distanceMeters <= 600) return 15;
    if (distanceMeters <= 1200) return 20;
    return 25;
  }
}
