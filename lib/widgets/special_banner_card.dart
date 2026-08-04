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
import 'package:cached_network_image/cached_network_image.dart';

class SpecialBannerCard extends StatefulWidget {
  /// A list of image URLs for the promotional banners.
  final List<String> imageUrls;

  /// Callback action triggered when a specific banner is tapped, passing its index.
  final Function(int index)? onTap;

  /// Height of the banner slider (defaults to 180).
  final double height;

  /// Side padding for the banner layout (defaults to 8.0).
  final double horizontalPadding;

  /// Corner roundness of the banner cards (defaults to 16.0).
  final double borderRadius;

  const SpecialBannerCard({
    super.key,
    required this.imageUrls,
    this.onTap,
    this.height = 180,
    this.horizontalPadding = 8.0,
    this.borderRadius = 16.0,
  });

  @override
  State<SpecialBannerCard> createState() => _SpecialBannerCardState();
}

class _SpecialBannerCardState extends State<SpecialBannerCard> {
  late final PageController _pageController;
  late final Timer _timer;
  int _currentPage = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);

    // Set up an automatic timer to slide to the next banner every 4 seconds
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_disposed || widget.imageUrls.isEmpty) return;

      if (_currentPage < widget.imageUrls.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer.cancel(); // Cancel the timer to prevent memory leaks
    _pageController.dispose(); // Dispose the controller safely
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
      child: Center(
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Swipeable PageView container
              ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.imageUrls.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => widget.onTap?.call(index),
                      // Phase 13: CachedNetworkImage so banner images are
                      // cached locally and never re-downloaded on every
                      // Home screen rebuild / page swipe.
                      child: CachedNetworkImage(
                        imageUrl: widget.imageUrls[index],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        // Lightweight placeholder while loading.
                        placeholder: (context, url) =>
                            Container(color: Colors.grey.shade300),
                        // Graceful fallback when the image fails to load
                        // (network error, 404, or test environment).
                        errorWidget: (context, url, error) =>
                            Container(color: Colors.grey.shade300),
                      ),
                    );
                  },
                ),
              ),

              // Page Dot Indicators
              if (widget.imageUrls.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.imageUrls.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        height: 8.0,
                        width: _currentPage == index
                            ? 24.0
                            : 8.0, // Expanded active dot
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? Colors.orange
                              : Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
