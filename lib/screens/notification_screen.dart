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
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';


/// UI icon/color mapping for notification types.
/// Kept separate from the model to avoid UI dependencies in pure data classes.
class NotificationVisuals {
  static ({IconData icon, Color color}) forType(NotificationType type) {
    switch (type) {
      case NotificationType.orderAccepted:
        return (icon: Icons.check_circle_outline, color: const Color(0xFF2E7D32));
      case NotificationType.orderPreparing:
        return (icon: Icons.restaurant_outlined, color: const Color(0xFF6D4C41));
      case NotificationType.orderReady:
        return (icon: Icons.rocket_launch_outlined, color: const Color(0xFF1B5E20));
      case NotificationType.pickupReminder:
        return (icon: Icons.access_time, color: const Color(0xFFE65100));
      case NotificationType.orderNoShow:
        return (icon: Icons.cancel_outlined, color: const Color(0xFFC62828));
      case NotificationType.orderCancelled:
        return (icon: Icons.close, color: const Color(0xFF6A1B9A));
      case NotificationType.accountSuspended:
        return (icon: Icons.block, color: const Color(0xFFC62828));
      case NotificationType.accountReactivated:
        return (icon: Icons.check_circle, color: const Color(0xFF2E7D32));
      case NotificationType.newOrder:
        return (icon: Icons.shopping_bag_outlined, color: const Color(0xFF1565C0));
      case NotificationType.notice:
        return (icon: Icons.notifications_none, color: const Color(0xFF546E7A));
    }
  }
}

/// Notification screen — displays the student's notifications with
/// options to mark as read and delete.
///
/// Uses Firestore streams for real-time updates.
/// Follows the Phase 7 architecture: business logic stays in
/// NotificationService, and widgets only handle presentational concerns.
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final NotificationService _notificationService = NotificationService();
  StreamSubscription<List<NotificationModel>>? _notificationsSubscription;
  StreamSubscription<int>? _unreadCountSubscription;

  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  bool _loading = true;
  String? _error;
  String? _userId;
  final String _userRole = NotificationService.roleStudent;

  @override
  void initState() {
    super.initState();
    _setupUserAndStream();
  }

  void _setupUserAndStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Please sign in to view notifications.';
      });
      return;
    }

    _userId = user.uid;

    _notificationsSubscription = _notificationService
        .notificationsStream(
          recipientId: user.uid,
          recipientRole: _userRole,
        )
        .listen(
          (notifications) {
            if (!mounted) return;
            setState(() {
              _notifications = notifications;
              _loading = false;
              _error = null;
            });
          },
          onError: (err) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = 'Failed to load notifications. Pull to retry.';
            });
          },
        );

    _unreadCountSubscription = _notificationService
        .unreadCountStream(
          recipientId: user.uid,
          recipientRole: _userRole,
        )
        .listen(
          (count) {
            if (!mounted) return;
            setState(() => _unreadCount = count);
          },
        );
  }

  @override
  void dispose() {
    _notificationsSubscription?.cancel();
    _unreadCountSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleMarkAsRead(String notificationId) async {
    await _notificationService.markAsRead(notificationId);
  }

  Future<void> _handleMarkAllAsRead() async {
    if (_userId == null) return;
    final success = await _notificationService.markAllAsRead(
      recipientId: _userId!,
      recipientRole: _userRole,
    );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All notifications marked as read'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleDelete(String notificationId) async {
    final success = await _notificationService.softDelete(notificationId);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification dismissed'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleClearAll() async {
    if (_userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Notifications?'),
        content: const Text(
          'This will dismiss all notifications. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final success = await _notificationService.clearAll(
      recipientId: _userId!,
      recipientRole: _userRole,
    );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All notifications cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleNotificationTap(NotificationModel notification) async {
    // Mark as read on tap
    if (!notification.read) {
      await _handleMarkAsRead(notification.id);
    }

    // Navigate via deep link if present
    final deepLink = notification.deepLink;
    if (deepLink != null && deepLink.isNotEmpty && mounted) {
      _navigateDeepLink(deepLink);
    }
  }

  void _navigateDeepLink(String deepLink) {
    try {
      final tabIndex = deepLinkToTabIndex(deepLink);

      if (tabIndex != null) {
        // Pop back to MainScreen and switch to the correct tab.
        // Using GoRouter to navigate to /main with the tab query parameter.
        if (mounted) {
          context.go('/main?tab=$tabIndex');
        }
      }
      // For null tabIndex (e.g., '/notifications'), stay on the current screen.
    } on Exception catch (_) {
      // Fallback: pop back to main screen
      try {
        if (mounted) Navigator.pop(context);
      } on Exception catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey[900],
          ),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton.icon(
              onPressed: _handleMarkAllAsRead,
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Mark all read'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[700],
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          if (_notifications.isNotEmpty)
            IconButton(
              onPressed: _handleClearAll,
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear all',
              color: Colors.grey[700],
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _notifications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 15),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _setupUserAndStream,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.notifications_none, size: 48, color: Colors.grey[400]),
            ),
            const SizedBox(height: 20),
            Text(
              'No notifications yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ll see updates about your orders here.',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        // Stream-based; refreshing re-triggers the stream
        _setupUserAndStream();
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _notifications.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final notification = _notifications[index];
          return _NotificationTile(
            notification: notification,
            onTap: () => _handleNotificationTap(notification),
            onMarkRead: !notification.read
                ? () => _handleMarkAsRead(notification.id)
                : null,
            onDelete: () => _handleDelete(notification.id),
          );
        },
      ),
    );
  }
  
  Object? deepLinkToTabIndex(String deepLink) {
    return null;
  }
}

/// A single notification list tile.
class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback? onMarkRead;
  final VoidCallback onDelete;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
    this.onMarkRead,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final visuals = NotificationVisuals.forType(notification.type);
    final isUnread = !notification.read;

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: isUnread ? Colors.blue.withValues(alpha: 0.04) : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: visuals.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(visuals.icon, color: visuals.color, size: 22),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400,
                              color: Colors.grey[900],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2E7D32),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // Message
                    Text(
                      notification.message,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Timestamp
                    Text(
                      _formatTimestamp(notification.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),

              // Actions
              PopupMenuButton<String>(
                iconSize: 18,
                color: Colors.grey[700],
                onSelected: (value) {
                  switch (value) {
                    case 'mark_read':
                      onMarkRead?.call();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (context) => [
                  if (onMarkRead != null)
                    PopupMenuItem(
                      value: 'mark_read',
                      child: Row(
                        children: [
                          Icon(Icons.check, size: 18, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          Text('Mark as read', style: TextStyle(fontSize: 13, color: Colors.grey[800])),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
                        const SizedBox(width: 8),
                        Text('Dismiss', style: TextStyle(fontSize: 13, color: Colors.red[400])),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}
