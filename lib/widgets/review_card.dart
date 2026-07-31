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

/// A single review card displaying reviewer info, rating, tags, and comment.
///
/// If [isOwner] is true, shows Edit and Delete action buttons.
class ReviewCard extends StatelessWidget {
  final Review review;
  final bool isOwner;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ReviewCard({
    super.key,
    required this.review,
    this.isOwner = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reviewer header row
          Row(
            children: [
              // Avatar circle with initials
              CircleAvatar(
                radius: 20,
                backgroundColor: _avatarColor,
                child: Text(
                  _initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Name and date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            review.displayNameForCard,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (review.verifiedPurchase) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified,
                                  size: 11,
                                  color: Color(0xFF2E7D32),
                                ),
                                SizedBox(width: 2),
                                Text(
                                  'Verified Purchase',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF2E7D32),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formattedDate,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Owner actions
              if (isOwner) ...[
                _ActionButton(
                  icon: Icons.edit_outlined,
                  label: 'Edit Review',
                  onTap: onEdit,
                ),
                const SizedBox(width: 4),
                _ActionButton(
                  icon: Icons.delete_outline,
                  label: 'Delete Review',
                  onTap: onDelete,
                  color: Colors.red.shade400,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Star rating
          Semantics(
            label: '${review.rating} out of 5 stars',
            child: ExcludeSemantics(
              child: Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < review.rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: const Color(0xFF2E7D32),
                    size: 20,
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Template tags
          if (review.templateTags.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: review.templateTags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFE0B2)),
                  ),
                  child: Text(
                    tag,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5D4037),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],

          // Comment
          if (review.comment.isNotEmpty) ...[
            Text(
              review.comment,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _initials {
    final name = review.displayNameForCard;
    final parts = name.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts.length == 1 && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  Color get _avatarColor {
    final hash = review.displayNameForCard.hashCode;
    final colors = [
      const Color(0xFF2E7D32),
      const Color(0xFF2979FF),
      const Color(0xFF6A1B9A),
      const Color(0xFFE65100),
      const Color(0xFF00838F),
      const Color(0xFFAD1457),
      const Color(0xFF283593),
      const Color(0xFF4E342E),
    ];
    return colors[hash.abs() % colors.length];
  }

  String get _formattedDate {
    if (review.createdAt == null) return 'Just now';
    final date = review.createdAt!;
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

/// Small circular icon button for edit/delete actions.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final String label;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.color = const Color(0xFF757575),
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
