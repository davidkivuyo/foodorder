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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/error_service.dart';

/// Network image that reports load timing/failures to [ImageMonitor]
/// (Phase 17 — Part 10).
///
/// Once a URL has failed this session it is rendered as the placeholder
/// directly — the network is not retried for known-broken URLs.
class MonitoredNetworkImage extends StatefulWidget {
  const MonitoredNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  State<MonitoredNetworkImage> createState() => _MonitoredNetworkImageState();
}

class _MonitoredNetworkImageState extends State<MonitoredNetworkImage> {
  bool _reportedEnd = false;
  bool _reportedPlaceholder = false;

  /// Starts tracking [url] unless it is already known broken. Known-broken
  /// URLs render the placeholder directly (no network request), so they never
  /// reach [ImageMonitor.reportLoadEnd] — tracking them would leave a pending
  /// measurement that only disposal could clear.
  void _startMonitoring(String url) {
    if (!ImageMonitor.instance.isKnownBroken(url)) {
      ImageMonitor.instance.reportLoadStart(url);
    }
  }

  @override
  void initState() {
    super.initState();
    _startMonitoring(widget.imageUrl);
  }

  @override
  void didUpdateWidget(MonitoredNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrl != oldWidget.imageUrl) {
      // A new image load begins — drop the previous URL's pending
      // measurement and reset the per-load reporting state so the new load
      // is tracked cleanly.
      ImageMonitor.instance.cancelPending(oldWidget.imageUrl);
      _reportedEnd = false;
      _reportedPlaceholder = false;
      _startMonitoring(widget.imageUrl);
    }
  }

  @override
  void dispose() {
    // If the widget is disposed mid-load (e.g. scrolled away) the pending
    // measurement must not leak in ImageMonitor.
    ImageMonitor.instance.cancelPending(widget.imageUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl;
    if (ImageMonitor.instance.isKnownBroken(url)) {
      // The known-broken branch renders on every rebuild — report the
      // placeholder exactly once per image load, matching the loading
      // path's guard. The flag is reset in didUpdateWidget on URL change.
      if (!_reportedPlaceholder) {
        _reportedPlaceholder = true;
        ImageMonitor.instance.reportPlaceholderShown();
      }
      return _errorPlaceholder(widget.width, widget.height);
    }
    return Image(
      image: CachedNetworkImageProvider(url),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          if (!_reportedEnd) {
            _reportedEnd = true;
            ImageMonitor.instance.reportLoadEnd(url, fromCache: false);
          }
          return child;
        }
        // The loadingBuilder may run many times per load (one rebuild per
        // progress event) — report the placeholder exactly once per load.
        if (!_reportedPlaceholder) {
          _reportedPlaceholder = true;
          ImageMonitor.instance.reportPlaceholderShown();
        }
        return _loadingPlaceholder(widget.width, widget.height);
      },
      errorBuilder: (context, error, stackTrace) {
        ImageMonitor.instance.reportFailure(url);
        return _errorPlaceholder(widget.width, widget.height);
      },
    );
  }

  Widget _loadingPlaceholder(double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _errorPlaceholder(double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade100,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: Colors.grey.shade400,
            size: (width != null && width < 100) ? 24 : 36,
          ),
          if (width == null || width >= 100) ...[
            const SizedBox(height: 4),
            const Text(
              'Image unavailable',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
