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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/pickup_window_service.dart';
import '../services/app_log.dart';
import '../widgets/monitored_network_image.dart';

class CafeDetailsScreen extends StatefulWidget {
  final String cafeName;

  const CafeDetailsScreen({super.key, required this.cafeName});

  @override
  State<CafeDetailsScreen> createState() => _CafeDetailsScreenState();
}

class _CafeDetailsScreenState extends State<CafeDetailsScreen> {
  /// Stable, OSM-policy-compliant tile User-Agent; version is resolved from
  /// the installed build so identification stays distinct and up to date.
  static const String _tileUserAgentFallback =
      'CampusBite/unknown (+https://foodapp.larason.space; contact: lembotor6@gmail.com)';

  String _tileUserAgent = _tileUserAgentFallback;
  double? _distanceMeters;
  bool _calculatingDistance = true;
  LatLng? _userPosition;

  @override
  void initState() {
    super.initState();
    _calculateDistance();
    _resolveTileUserAgent();
  }

  Future<void> _resolveTileUserAgent() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isEmpty) return;
      _tileUserAgent =
          'CampusBite/$version (+https://foodapp.larason.space; contact: lembotor6@gmail.com)';
      if (mounted) setState(() {});
    } catch (_) {
      // Keep the fallback; identity must stay stable even if the lookup fails.
    }
  }

  /// Calculates user distance to cafe using Geolocator without storing user location anywhere.
  Future<void> _calculateDistance() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _calculatingDistance = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        final cafeQuery = await FirebaseFirestore.instance
            .collection('cafes')
            .where('name', isEqualTo: widget.cafeName)
            .limit(1)
            .get();

        if (cafeQuery.docs.isNotEmpty) {
          final cafeData = cafeQuery.docs.first.data();
          final GeoPoint? cafeGeo = cafeData['geoLocation'] as GeoPoint?;
          if (cafeGeo != null) {
            final dist = PickupWindowService.calculateDistance(
              startLatitude: position.latitude,
              startLongitude: position.longitude,
              endLatitude: cafeGeo.latitude,
              endLongitude: cafeGeo.longitude,
            );
            if (mounted) {
              setState(() {
                _distanceMeters = dist;
                _userPosition = LatLng(position.latitude, position.longitude);
                _calculatingDistance = false;
              });
            }
            return;
          }
        }
      }
    } catch (e) {
      AppLog.e('[CafeDetailsScreen] Error calculating distance', e);
    }
    if (mounted) {
      setState(() => _calculatingDistance = false);
    }
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km away';
    }
    return '${meters.round()} m away';
  }

  String _formatOperatingHours(String openAt, String closingAt) {
    String openStr = _parseTimeString(openAt);
    String closeStr = _parseTimeString(closingAt);
    if (openStr.isEmpty && closeStr.isEmpty) {
      return 'Operating hours not specified';
    }
    return '$openStr - $closeStr';
  }

  String _parseTimeString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is Timestamp) {
      final dt = value.toDate();
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    return value.toString().trim();
  }

  bool _isCurrentlyOpen(String openAt, String closingAt) {
    final openStr = _parseTimeString(openAt);
    final closeStr = _parseTimeString(closingAt);
    if (openStr.isEmpty || closeStr.isEmpty) return true;

    try {
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;

      final openParts = openStr.split(':');
      final openMinutes =
          int.parse(openParts[0]) * 60 + int.parse(openParts[1]);

      final closeParts = closeStr.split(':');
      final closeMinutes =
          int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);

      if (closeMinutes >= openMinutes) {
        return nowMinutes >= openMinutes && nowMinutes <= closeMinutes;
      } else {
        // Overnight hours
        return nowMinutes >= openMinutes || nowMinutes <= closeMinutes;
      }
    } catch (_) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          widget.cafeName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('cafes')
            .where('name', isEqualTo: widget.cafeName)
            .limit(1)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load cafe details.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Information for "${widget.cafeName}" is not available yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final cafeData = docs.first.data() as Map<String, dynamic>;
          final description = cafeData['description'] as String? ?? '';
          final imageUrl =
              cafeData['image'] as String? ??
              cafeData['imageUrl'] as String? ??
              '';
          final GeoPoint? geoPoint = cafeData['geoLocation'] as GeoPoint?;
          final openAt = cafeData['openAt']?.toString() ?? '';
          final closingAt = cafeData['closingAt']?.toString() ?? '';

          final isOpen = _isCurrentlyOpen(openAt, closingAt);
          final hoursText = _formatOperatingHours(openAt, closingAt);

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Image
                if (imageUrl.isNotEmpty)
                  SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: MonitoredNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    height: 140,
                    width: double.infinity,
                    color: Colors.orange.shade50,
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 64,
                      color: Colors.orange.shade300,
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cafe Name and Status
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              widget.cafeName,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isOpen
                                  ? const Color(0xFFE8F5E9)
                                  : const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isOpen ? 'Open Now' : 'Closed',
                              style: TextStyle(
                                color: isOpen
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFC62828),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Distance & Hours Info Cards
                      Row(
                        children: [
                          // Distance card
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.directions_walk_rounded,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Distance',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _calculatingDistance
                                              ? 'Calculating...'
                                              : (_distanceMeters != null
                                                    ? _formatDistance(
                                                        _distanceMeters!,
                                                      )
                                                    : 'Location off'),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Hours card
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.access_time_rounded,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Hours',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          hoursText,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'About Cafe',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                            height: 1.5,
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),
                      const Text(
                        'Location',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // OpenStreetMap Section
                      if (geoPoint != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 240,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: _userPosition != null
                                    ? LatLng(
                                        (geoPoint.latitude +
                                                _userPosition!.latitude) /
                                            2,
                                        (geoPoint.longitude +
                                                _userPosition!.longitude) /
                                            2,
                                      )
                                    : LatLng(
                                        geoPoint.latitude,
                                        geoPoint.longitude,
                                      ),
                                initialZoom: _userPosition != null
                                    ? 15.0
                                    : 16.5,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: _tileUserAgent,
                                  tileProvider: NetworkTileProvider(
                                    headers: {'User-Agent': _tileUserAgent},
                                  ),
                                ),
                                if (_userPosition != null)
                                  PolylineLayer(
                                    polylines: [
                                      Polyline(
                                        points: [
                                          _userPosition!,
                                          LatLng(
                                            geoPoint.latitude,
                                            geoPoint.longitude,
                                          ),
                                        ],
                                        strokeWidth: 4.0,
                                        color: Colors.orange.shade700,
                                      ),
                                    ],
                                  ),
                                MarkerLayer(
                                  markers: [
                                    if (_userPosition != null)
                                      Marker(
                                        point: _userPosition!,
                                        width: 36,
                                        height: 36,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade600,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 3,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black26,
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.my_location_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    Marker(
                                      point: LatLng(
                                        geoPoint.latitude,
                                        geoPoint.longitude,
                                      ),
                                      width: 40,
                                      height: 40,
                                      child: const Icon(
                                        Icons.location_on,
                                        color: Colors.red,
                                        size: 40,
                                      ),
                                    ),
                                  ],
                                ),
                                RichAttributionWidget(
                                  attributions: [
                                    TextSourceAttribution(
                                      'OpenStreetMap contributors',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: Text(
                            'Map data © OpenStreetMap contributors',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.location_off_outlined,
                                color: Colors.grey,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Geo-coordinates not recorded for this cafe.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
