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
import 'package:firebase_auth/firebase_auth.dart';
import '../data/food_data.dart';
import '../models/review.dart';
import '../services/review_service.dart';
import '../widgets/review_card.dart';
import '../widgets/add_review_dialog.dart';

/// Displays reviews for a food item with a Deliveroo-style rating dashboard.
///
/// Shows:
/// - Average rating with star display
/// - Total review count
/// - 5-star distribution bars
/// - Sortable, paginated review list
/// - Edit/Delete controls for the current user's reviews
class ReviewsScreen extends StatefulWidget {
  final FoodItem foodItem;

  const ReviewsScreen({super.key, required this.foodItem});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  final ReviewService _reviewService = ReviewService();
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  // Sort state
  String _sortOrder = 'createdAt';
  bool _sortDescending = true;

  // Request generation token — incremented on sort change so stale
  // async responses from a previous sort are discarded.
  int _requestGeneration = 0;

  // Pagination state
  List<Review> _reviews = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _loadFailed = false;
  final ScrollController _scrollController = ScrollController();

  // Food rating stats (live from the food item document)
  double _averageRating = 0.0;
  int _reviewCount = 0;
  Map<String, dynamic>? _ratingDistribution;
  StreamSubscription<DocumentSnapshot>? _foodStatsSub;

  @override
  void initState() {
    super.initState();
    _loadReviews();
    _loadFoodStats();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _foodStatsSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadMore();
    }
  }

  void _loadFoodStats() {
    // Listen to food item document for live rating-stat updates via
    // ReviewService rather than directly accessing Firestore.
    _foodStatsSub = _reviewService
        .watchFoodStats(widget.foodItem.id)
        .listen(
          (snapshot) {
            if (snapshot.exists && mounted) {
              final data = snapshot.data() as Map<String, dynamic>?;
              if (data == null) return;
              setState(() {
                _averageRating =
                    (data['averageRating'] as num?)?.toDouble() ?? 0.0;
                _reviewCount = (data['reviewCount'] as num?)?.toInt() ?? 0;
                _ratingDistribution =
                    data['ratingDistribution'] as Map<String, dynamic>?;
              });
            }
          },
          onError: (Object error, StackTrace stack) {
            debugPrint('[ReviewsScreen] foodStats stream error: $error');
            // Keep the existing default values (0.0, 0, null) so the UI
            // degrades gracefully instead of crashing.
          },
        );
  }

  /// Sort option labels.
  String get _sortLabel {
    switch (_sortOrder) {
      case 'createdAt':
        return _sortDescending ? 'Most Recent' : 'Oldest';
      case 'rating':
        return _sortDescending ? 'Highest Rated' : 'Lowest Rated';
      default:
        return 'Most Recent';
    }
  }

  void _changeSort(String orderBy, bool descending) {
    _requestGeneration++;
    setState(() {
      _sortOrder = orderBy;
      _sortDescending = descending;
      _reviews = [];
      _lastDoc = null;
      _hasMore = true;
      _isLoading = false; // unblock so the new fetch can proceed
      _loadFailed = false;
    });
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    if (_isLoading) return;
    final generation = _requestGeneration;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    try {
      final result = await _reviewService.fetchFoodReviews(
        foodId: widget.foodItem.id,
        limit: 20,
        lastDoc: null,
        orderBy: _sortOrder,
        descending: _sortDescending,
      );

      if (!mounted || generation != _requestGeneration) return;

      setState(() {
        _reviews = result.key;
        _lastDoc = result.value;
        _hasMore = result.key.length >= 20;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[ReviewsScreen] load error: $e');
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    final generation = _requestGeneration;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    try {
      final result = await _reviewService.fetchFoodReviews(
        foodId: widget.foodItem.id,
        limit: 20,
        lastDoc: _lastDoc,
        orderBy: _sortOrder,
        descending: _sortDescending,
      );

      if (!mounted || generation != _requestGeneration) return;

      setState(() {
        _reviews.addAll(result.key);
        _lastDoc = result.value;
        _hasMore = result.key.length >= 20;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[ReviewsScreen] loadMore error: $e');
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _deleteReview(Review review) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Review'),
        content: const Text('Are you sure you want to delete your review?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _reviewService.deleteReview(
          reviewId: review.id,
          foodId: review.foodId,
        );
      } catch (e) {
        debugPrint('[ReviewsScreen] deleteReview error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete review.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return; // Don't remove from list on failure
      }
      // Remove from local list only on success
      if (mounted) {
        setState(() {
          _reviews.removeWhere((r) => r.id == review.id);
        });
      }
    }
  }

  Future<void> _editReview(Review review) async {
    final result = await showModalBottomSheet<ReviewResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddReviewDialog(
        existingReview: review,
        foodTitle: widget.foodItem.title,
      ),
    );

    if (result != null) {
      try {
        await _reviewService.updateReview(
          reviewId: review.id,
          foodId: review.foodId,
          rating: result.rating,
          templateTags: result.templateTags,
          comment: result.comment,
          anonymous: result.anonymous,
        );
      } catch (e) {
        debugPrint('[ReviewsScreen] updateReview error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update review.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return; // Don't reload on failure
      }
      // Reload reviews only on success
      _loadReviews();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Reviews',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // ── Rating Dashboard ──────────────────────────────────────────
          if (_reviewCount > 0)
            _buildRatingDashboard()
          else
            _buildEmptyDashboard(),

          const Divider(thickness: 8, color: Color(0xFFF5F5F5)),

          // ── Sort & Filter Bar ─────────────────────────────────────────
          _buildSortBar(),

          // ── Reviews List ──────────────────────────────────────────────
          Expanded(
            child: _reviews.isEmpty && !_isLoading
                ? (_loadFailed
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 84),
                          child: _buildLoadError(),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 84),
                          child: _buildEmptyState(),
                        ))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 84),
                    controller: _scrollController,
                    itemCount: _reviews.length + (_isLoading ? 1 : 0),
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: Color(0xFFEEEEEE),
                    ),
                    itemBuilder: (context, index) {
                      if (index >= _reviews.length) {
                        // Loading indicator at the bottom
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ),
                        );
                      }
                      final review = _reviews[index];
                      return ReviewCard(
                        review: review,
                        isOwner: review.userId == _currentUserId,
                        onEdit: review.userId == _currentUserId
                            ? () => _editReview(review)
                            : null,
                        onDelete: review.userId == _currentUserId
                            ? () => _deleteReview(review)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),

      // ── Bottom Button ─────────────────────────────────────────────────
      bottomSheet: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16.0),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Back to menu',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Dashboard Builders ─────────────────────────────────────────────────────

  Widget _buildEmptyDashboard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.rate_review_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            const Text(
              'No reviews yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Be the first to review this item',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingDashboard() {
    final percentages = ReviewService.distributionPercentages(
      _ratingDistribution,
      _reviewCount,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left side — average score
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _averageRating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B5E20),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  final star = index + 1;
                  return Icon(
                    star <= _averageRating.floor()
                        ? Icons.star_rounded
                        : (star - 0.5 <= _averageRating
                              ? Icons.star_half_rounded
                              : Icons.star_border_rounded),
                    color: Colors.orange,
                    size: 18,
                  );
                }),
              ),
              const SizedBox(height: 4),
              Text(
                _reviewCount == 1
                    ? '$_reviewCount review'
                    : '$_reviewCount reviews',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(width: 24),

          // Right side — rating bars
          Expanded(
            child: Column(
              children: [
                _buildRatingBar('5', percentages['5'] ?? 0.0),
                _buildRatingBar('4', percentages['4'] ?? 0.0),
                _buildRatingBar('3', percentages['3'] ?? 0.0),
                _buildRatingBar('2', percentages['2'] ?? 0.0),
                _buildRatingBar('1', percentages['1'] ?? 0.0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingBar(String label, double percentage) {
    // Convert percentage (0–100) to fraction (0–1) for the progress indicator
    final fraction = (percentage / 100.0).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                backgroundColor: const Color(0xFFE0E0E0),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF1B5E20),
                ),
                minHeight: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sort Bar ───────────────────────────────────────────────────────────────

  Widget _buildSortBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _reviewCount > 0 ? 'All reviews' : 'Reviews',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          if (_reviewCount > 0)
            PopupMenuButton<String>(
              offset: const Offset(0, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (value) {
                switch (value) {
                  case 'recent':
                    _changeSort('createdAt', true);
                    break;
                  case 'oldest':
                    _changeSort('createdAt', false);
                    break;
                  case 'highest':
                    _changeSort('rating', true);
                    break;
                  case 'lowest':
                    _changeSort('rating', false);
                    break;
                }
              },
              itemBuilder: (context) => [
                _sortOption('Most Recent', 'recent'),
                _sortOption('Oldest', 'oldest'),
                _sortOption('Highest Rated', 'highest'),
                _sortOption('Lowest Rated', 'lowest'),
              ],
              child: Row(
                children: [
                  Text(
                    _sortLabel,
                    style: const TextStyle(
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: Color(0xFF2E7D32),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _sortOption(String label, String value) {
    return PopupMenuItem(value: value, child: Text(label));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.rate_review_outlined,
            size: 56,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          const Text(
            'No reviews yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'There are no reviews for this item yet.',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'Failed to load reviews',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Check your connection and try again.',
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              _loadReviews();
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
