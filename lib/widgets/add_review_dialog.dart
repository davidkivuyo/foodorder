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
import '../models/review.dart';

/// A bottom-sheet dialog for writing or editing a food review.
///
/// Shows:
/// - Star rating selector (1-5)
/// - Predefined template tags (max 5 selectable)
/// - Optional comment (max 120 chars)
/// - Anonymous toggle
///
/// Returns a [ReviewResult] when submitted, or null if cancelled.
class AddReviewDialog extends StatefulWidget {
  /// If provided, the dialog opens in "Edit" mode with pre-filled values.
  final Review? existingReview;
  final String foodTitle;

  const AddReviewDialog({
    super.key,
    this.existingReview,
    required this.foodTitle,
  });

  @override
  State<AddReviewDialog> createState() => _AddReviewDialogState();
}

class _AddReviewDialogState extends State<AddReviewDialog> {
  late int _rating;
  late Set<String> _selectedTags;
  late TextEditingController _commentController;
  late bool _anonymous;
  bool _isSubmitting = false;

  bool get _isEditMode => widget.existingReview != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingReview;
    _rating = existing?.rating ?? 5;
    _selectedTags = Set.from(existing?.templateTags ?? []);
    _commentController = TextEditingController(text: existing?.comment ?? '');
    _anonymous = existing?.anonymous ?? true;
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else if (_selectedTags.length < 5) {
        _selectedTags.add(tag);
      }
    });
  }

  bool get _canSubmit => _rating >= 1 && _rating <= 5;

  void _submit() {
    if (!_canSubmit || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    // The flag and setState prevent rapid repeated taps from triggering
    // multiple Navigator.pop calls before the route is removed from the
    // widget tree. The spinner and disabled-button state in the UI become
    // reachable, providing immediate visual feedback.
    Navigator.of(context).pop(
      ReviewResult(
        rating: _rating,
        templateTags: _selectedTags.toList(),
        comment: _commentController.text.trim(),
        anonymous: _anonymous,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.black),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              _isEditMode ? 'Edit Review' : 'Write a Review',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            centerTitle: false,
            actions: [
              TextButton(
                onPressed: _isSubmitting ? null : _submit,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _isEditMode ? 'Update' : 'Submit',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Food title
                Text(
                  widget.foodTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),

                // Star rating
                const Text(
                  'Rating',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final starValue = index + 1;
                    return GestureDetector(
                      onTap: () => setState(() => _rating = starValue),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          starValue <= _rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 40,
                          color: starValue <= _rating
                              ? Colors.amber
                              : Colors.grey.shade300,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _ratingLabel(_rating),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Template tags
                const Text(
                  'How was it? (Select up to 5)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_selectedTags.length}/5 selected',
                  style: TextStyle(
                    fontSize: 13,
                    color: _selectedTags.length >= 5
                        ? Colors.orange
                        : Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reviewTemplateTags.map((tag) {
                    final isSelected = _selectedTags.contains(tag);
                    return GestureDetector(
                      onTap: () => _toggleTag(tag),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF2E7D32)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                isSelected ? Colors.white : Colors.black87,
                            fontWeight:
                                isSelected ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Optional comment
                const Text(
                  'Add a comment (optional)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentController,
                  maxLength: 120,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Share your experience...',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF2E7D32),
                        width: 2,
                      ),
                    ),
                    counterStyle: TextStyle(color: Colors.grey.shade500),
                  ),
                ),
                const SizedBox(height: 16),

                // Anonymous toggle
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Display my name',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _anonymous
                                  ? 'Your review will show as "CampusBite Customer"'
                                  : 'Your real name will be shown',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: !_anonymous,
                        onChanged: (value) {
                          setState(() => _anonymous = !value);
                        },
                        activeTrackColor: const Color(0xFF2E7D32),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return '';
    }
  }
}

/// Result data from the [AddReviewDialog].
class ReviewResult {
  final int rating;
  final List<String> templateTags;
  final String comment;
  final bool anonymous;

  const ReviewResult({
    required this.rating,
    required this.templateTags,
    this.comment = '',
    this.anonymous = true,
  });
}
