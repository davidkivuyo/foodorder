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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/strike_service.dart';
import '../models/strike_model.dart';
import '../widgets/logout_confirmation_dialog.dart';
import 'notification_screen.dart';
import 'order_screen.dart';

export 'notification_screen.dart' show NotificationScreen;

// ── Avatar helpers ──────────────────────────────────────────────────────────

/// Returns uppercase initials from a full name.
/// Single name  → first letter only  example "lembotor" → "L")
/// Multiple names → first letter of each of the first two words example "Lembotor larabal" → "LL")
String _initialsFromName(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// Deterministically picks one of several curated colours based on the name.
/// The same name always produces the same colour.
Color _avatarColorFromName(String name) {
  const List<Color> palette = [
    Color(0xFFE53935), // red
    Color(0xFF8E24AA), // purple
    Color(0xFF1E88E5), // blue
    Color(0xFF00897B), // teal
    Color(0xFF43A047), // green
    Color(0xFFF4511E), // deep orange
    Color(0xFF6D4C41), // brown
    Color(0xFF3949AB), // indigo
    Color(0xFF00ACC1), // cyan
    Color(0xFFFF8F00), // amber
  ];
  if (name.isEmpty) return palette[0];
  final index = name.codeUnits.fold(0, (acc, c) => acc + c) % palette.length;
  Color base = palette[index];
  // If the colour is too light, darken it for better contrast.
  if (base.computeLuminance() > 0.5) {
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0)).toColor();
  }
  return base;
}

//account screen
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final user = authService.currentUser;
    String name = (user?.displayName != null && user!.displayName!.isNotEmpty)
        ? user.displayName!
        : 'Campus Bite User';

    String email = user?.email ?? 'No email found';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "What's your bite today?",
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                    ),
                    if (user != null)
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: StrikeService().strikeStream(user.uid),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || !snapshot.data!.exists) {
                            return const SizedBox.shrink();
                          }
                          final doc = snapshot.requireData;
                          final percentage = StrikeService.extractStrikePercentage(doc);
                          final displayStatus = displayStatusFromPercentage(percentage);

                          final Color textColor;
                          switch (displayStatus) {
                            case StrikeDisplayStatus.active:
                              textColor = Colors.green.shade700;
                              break;
                            case StrikeDisplayStatus.warning:
                              textColor = Colors.orange.shade800;
                              break;
                            case StrikeDisplayStatus.suspended:
                              textColor = Colors.red.shade700;
                              break;
                          }

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: textColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$percentage%',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: user != null
                      ? FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .snapshots()
                      : null,
                  builder: (context, snapshot) {
                    String displayName = name;
                    String displayEmail = email;
                    // Canonical name used for avatar identity.
                    final authFullName = user?.displayName?.trim();
                    String rawFullName = authFullName?.isNotEmpty == true
                        ? authFullName!
                        : name;

                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data = snapshot.data!.data();
                      if (data != null) {
                        final fullName =
                            (data['fullName'] as String?)?.trim() ?? '';
                        if (fullName.isNotEmpty) {
                          rawFullName = fullName;
                          displayName = fullName.split(RegExp(r'\s+')).first;
                        }
                        displayEmail = data['email'] as String? ?? displayEmail;
                      }
                    } else {
                      // Fallback to FirebaseAuth user properties if snapshot not ready/doesn't exist
                      final displayNameValue = user?.displayName?.trim();
                      if (displayNameValue != null &&
                          displayNameValue.isNotEmpty) {
                        rawFullName = displayNameValue;
                        displayName = displayNameValue
                            .split(RegExp(r'\s+'))
                            .first;
                      }
                    }

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _UserInitialsAvatar(
                              initials: _initialsFromName(rawFullName),
                              color: _avatarColorFromName(rawFullName),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.email_outlined, size: 15),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    displayEmail,
                                    style: const TextStyle(fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),

                AccountSettings(),

                const SizedBox(height: 18),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Campus Bite v1.0.0 (alpha)',
                        style: TextStyle(fontSize: 10),
                      ),
                      Text(
                        'Made with ❤️ for students',
                        style: TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A stylish rounded-border square avatar displaying a user's initials.
///
/// The [color] is the background fill; text is always white.
/// Size is fixed at 70×70 to match the removed image dimensions.
class _UserInitialsAvatar extends StatelessWidget {
  final String initials;
  final Color color;

  const _UserInitialsAvatar({required this.initials, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          // Darken the fill colour by 20 % lightness to create a visible,
          // contrasting border ring rather than a near-invisible tinted one.
          color: HSLColor.fromColor(color)
              .withLightness(
                (HSLColor.fromColor(color).lightness - 0.20).clamp(0.0, 1.0),
              )
              .toColor(),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(60),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class AccountSettings extends StatelessWidget {
  const AccountSettings({super.key});
  // Instantiate the auth service to access signOut
  static final _authService = AuthService();

  void _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const LogoutConfirmationDialog(),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _authService.signOut();
      if (!context.mounted) return;
      Navigator.of(
        context,
        rootNavigator: true,
      ).pop(); // close the loading dialog
      context.go('/');
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(
        context,
        rootNavigator: true,
      ).pop(); // close the loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to logout: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Account Settings',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              /* _settingTile(
                icon: Icons.edit_outlined,
                iconColor: Colors.green,
                background: Colors.green.shade50,
                title: 'Edit Profile',
                subtitle: 'Manage your personal information',
                onTap: () {},
              ),
              const Divider(height: 1),*/
              _settingTile(
                icon: Icons.receipt_long_outlined,
                iconColor: Colors.blue,
                background: Colors.blue.shade50,
                title: 'Order History',
                subtitle: 'View your previous orders',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OrdersScreen(),
                  ),
                ),
              ),

              const Divider(height: 1),

              _settingTile(
                icon: Icons.help_outline,
                iconColor: Colors.grey.shade700,
                background: Colors.grey.shade200,
                title: 'Help & Support',
                subtitle: 'FAQs and customer support',
                onTap: () => context.push('/support'),
              ),

              const Divider(height: 1),

              _settingTile(
                icon: Icons.privacy_tip_outlined,
                iconColor: Colors.grey.shade700,
                background: Colors.grey.shade200,
                title: 'Terms & Privacy',
                subtitle: 'Policies and usage guidelines',
                onTap: () => context.push('/terms'),
              ),

              const Divider(height: 1),

              _settingTile(
                icon: Icons.logout,
                iconColor: Colors.red,
                background: Colors.red.shade50,
                title: 'Logout',
                subtitle: 'Securely exit your account',
                titleColor: Colors.red,
                onTap: () => _handleLogout(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingTile({
    required IconData icon,
    required Color iconColor,
    required Color background,
    required String title,
    required String subtitle,
    Color titleColor = Colors.black87,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: background,
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, color: titleColor),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Legacy alias kept for backward compatibility.
///
/// The full notification screen has moved to notification_screen.dart.
/// @deprecated Use [NotificationScreen] instead.
class Notify extends StatelessWidget {
  const Notify({super.key});

  @override
  Widget build(BuildContext context) {
    return const NotificationScreen();
  }
}
