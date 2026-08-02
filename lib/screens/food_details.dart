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
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/food_data.dart';
import '../models/review.dart';
import '../services/app_log.dart';
import '../services/review_service.dart';
import '../widgets/cafe_selection_dialog.dart';
import '../widgets/stock_badge.dart';
import '../widgets/add_review_dialog.dart';
import 'reviews_screen.dart';

/// A reusable food item detail screen used from the home screen,
/// category screen, common food list, search results, and favourites.
///
/// [heroTagPrefix] must match the prefix used in the source card's [Hero]
/// tag so the Hero transition animation plays correctly.
class FoodDetailsScreen extends StatefulWidget {
  final FoodItem item;
  final String heroTagPrefix;

  const FoodDetailsScreen({
    super.key,
    required this.item,
    this.heroTagPrefix = 'home_',
  });

  @override
  State<FoodDetailsScreen> createState() => _FoodDetailsScreenState();
}

class _FoodDetailsScreenState extends State<FoodDetailsScreen> {
  int quantity = 1;
  final ReviewService _reviewService = ReviewService();

  // Review eligibility state
  bool _checkingEligibility = true;
  bool _isReviewable = false;
  bool _hasExistingReview = false;
  Review? _existingReview;
  String? _matchingOrderId; // For new reviews (no existing review yet)

  // Real-time ratings state
  double? _liveAverageRating;
  int? _liveReviewCount;
  StreamSubscription<DocumentSnapshot>? _foodStatsSub;

  double get _displayRating => _liveAverageRating ?? widget.item.averageRating;
  int get _displayReviewCount => _liveReviewCount ?? widget.item.reviewCount;

  @override
  void initState() {
    super.initState();
    _checkReviewEligibility();
    _listenToFoodStats();
  }

  @override
  void dispose() {
    _foodStatsSub?.cancel();
    super.dispose();
  }

  void _listenToFoodStats() {
    _foodStatsSub = _reviewService
        .watchFoodStats(widget.item.id)
        .listen(
          (snapshot) {
            if (snapshot.exists && mounted) {
              final data = snapshot.data() as Map<String, dynamic>?;
              if (data == null) return;
              setState(() {
                _liveAverageRating =
                    (data['averageRating'] as num?)?.toDouble() ?? 0.0;
                _liveReviewCount = (data['reviewCount'] as num?)?.toInt() ?? 0;
              });
            }
          },
          onError: (Object error, StackTrace stack) {
            AppLog.e('[FoodDetailsScreen] foodStats stream error', error);
          },
        );
  }

  Future<void> _checkReviewEligibility() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      if (mounted) setState(() => _checkingEligibility = false);
      return;
    }

    try {
      final eligibility = await _reviewService.checkEligibility(widget.item.id);
      if (mounted) {
        setState(() {
          _checkingEligibility = false;
          _isReviewable = eligibility.eligible;
          _hasExistingReview = eligibility.hasExistingReview;
          _existingReview = eligibility.existingReview;
          _matchingOrderId = eligibility.matchingOrderId;
        });
      }
    } catch (e) {
      AppLog.e('[FoodDetailsScreen] checkEligibility error', e);
      if (mounted) {
        setState(() {
          _checkingEligibility = false;
          _isReviewable = false;
          _hasExistingReview = false;
          _existingReview = null;
          _matchingOrderId = null;
        });
      }
    }
  }

  /// Open the review dialog and handle submit.
  Future<void> _openReviewDialog() async {
    final result = await showModalBottomSheet<ReviewResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddReviewDialog(
        existingReview: _hasExistingReview ? _existingReview : null,
        foodTitle: widget.item.title,
      ),
    );

    if (result == null) return;

    if (_hasExistingReview && _existingReview != null) {
      // ── Edit existing review ────────────────────────────────────────
      try {
        final success = await _reviewService.updateReview(
          reviewId: _existingReview!.id,
          foodId: widget.item.id,
          rating: result.rating,
          templateTags: result.templateTags,
          comment: result.comment,
          anonymous: result.anonymous,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success ? 'Review updated!' : 'Failed to update review.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        // Re-check eligibility only after a completed operation
        if (success) _checkReviewEligibility();
      } catch (e) {
        AppLog.e('[FoodDetailsScreen] updateReview error', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update review.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
      // ── Create a new review ─────────────────────────────────────────
      if (_matchingOrderId == null || _matchingOrderId!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to submit review.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      try {
        final docId = await _reviewService.createReview(
          foodId: widget.item.id,
          orderId: _matchingOrderId!,
          rating: result.rating,
          templateTags: result.templateTags,
          comment: result.comment,
          anonymous: result.anonymous,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                docId != null
                    ? 'Review submitted!'
                    : 'Failed to submit review.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        // Re-check eligibility only after a completed operation
        if (docId != null) _checkReviewEligibility();
      } catch (e) {
        AppLog.e('[FoodDetailsScreen] createReview error', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to submit review.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: CustomScrollView(
          slivers: [
            // Top Image Header with Back Button
            SliverAppBar(
              expandedHeight: 300.0,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag:
                          '${widget.heroTagPrefix}${item.displayCafe}_${item.title}_${item.image}',
                      child: item.buildImage(
                        width: double.infinity,
                        height: 300,
                        fit: BoxFit.cover,
                      ),
                    ),
                    // Stock overlay badge
                    StockOverlayBadge(inStock: item.available),
                    // "Bestseller" Badge - show only if featured
                    if (item.featured)
                      Positioned(
                        top: 100,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade700,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Bestseller',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Scrollable Content
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and Price
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Text(
                          'TZS ${item.price}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Subtitle
                    if (item.subtitle.isNotEmpty) ...[
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],

                    // Rating and Prep Time
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Colors.amber,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _displayRating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        if (item.time.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            '  •  ${item.time}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ],
                    ),

                    // Stock status inline
                    if (!item.available) ...[
                      const SizedBox(height: 8),
                      StockBadge(inStock: item.available, fontSize: 12),
                    ],

                    const SizedBox(height: 24),

                    // Description Section
                    if (item.description.isNotEmpty) ...[
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.description,
                        style: const TextStyle(
                          color: Colors.black54,
                          height: 1.5,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(height: 1, color: Color(0xFFEEEEEE)),
                      const SizedBox(height: 24),
                    ],

                    // Available Cafes
                    if (item.availableCafes.isNotEmpty) ...[
                      const Text(
                        'Available At',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...item.availableCafes.map(
                        (cafe) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.storefront_outlined,
                                size: 18,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                cafe,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(height: 1, color: Color(0xFFEEEEEE)),
                      const SizedBox(height: 24),
                    ],

                    // Dietary Tags
                    if (item.dietaryTags.isNotEmpty) ...[
                      const Text(
                        'Dietary Info',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: item.dietaryTags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Category
                    if (item.category.isNotEmpty) ...[
                      const Text(
                        'Category',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.category,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ── Review Section ───────────────────────────────────
                    if (_displayReviewCount > 0) ...[
                      _buildReviewSummaryRow(),
                      const SizedBox(height: 12),
                    ],

                    // Review button — shows if eligible
                    if (!_checkingEligibility && _isReviewable) ...[
                      _buildReviewButton(),
                      const SizedBox(height: 24),
                    ],

                    const SizedBox(height: 100), // Padding for bottom navbar
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // Bottom Bar with Counter and Add to Cart Button
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Quantity Counter Block
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: () {
                        if (quantity > 1) {
                          setState(() => quantity--);
                        }
                      },
                    ),
                    Text(
                      quantity.toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: () {
                        final maxQty = item.quantity > 0 ? item.quantity : 99;
                        if (quantity < maxQty) {
                          setState(() => quantity++);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Add to Cart Button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: item.available
                      ? () => addToCartWithCafeCheck(
                          context,
                          item,
                          quantity: quantity,
                        )
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: item.available
                        ? Colors.orange
                        : Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  icon: Icon(
                    item.available ? Icons.shopping_cart_outlined : Icons.block,
                    size: 20,
                  ),
                  label: Text(
                    item.available
                        ? 'Add to Cart • TZS ${(item.price * quantity)}'
                        : 'Unavailable',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
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

  // ── Review Helpers ─────────────────────────────────────────────────────────

  Widget _buildReviewSummaryRow() {
    final item = widget.item;
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReviewsScreen(foodItem: item),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FBE7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE6EE9C)),
        ),
        child: Row(
          children: [
            // Rating stars
            Row(
              children: List.generate(5, (index) {
                final star = index + 1;
                final avg = _displayRating;
                return Icon(
                  star <= avg.round()
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: Colors.amber,
                  size: 18,
                );
              }),
            ),
            const SizedBox(width: 8),
            Text(
              _displayRating.toStringAsFixed(1),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '($_displayReviewCount ${_displayReviewCount == 1 ? 'review' : 'reviews'})',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Color(0xFF2E7D32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _openReviewDialog,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        icon: Icon(
          _hasExistingReview ? Icons.edit_outlined : Icons.rate_review_outlined,
          size: 20,
        ),
        label: Text(
          _hasExistingReview ? 'Edit Review' : 'Write a Review',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
