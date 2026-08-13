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

import 'package:campusbite/models/pickup_reliability.dart';
import 'package:campusbite/models/user_profile.dart';
import 'package:campusbite/services/auth_service.dart';
import 'package:campusbite/widgets/pickup_reliability_card.dart';
import 'package:campusbite/widgets/user_initials_avatar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/logout_confirmation_dialog.dart';

class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});

  // Instantiate the auth service to access signOut and currentUser
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
    } on Exception catch (e) {
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

  void _handleResetPassword(BuildContext context, String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text(
          'Send password reset email to $email?\n\n'
          'For security, a verification email link will be dispatched to your registered address.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF168039),
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Email'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    await _authService.sendPasswordReset(email: email);

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'If an account exists, a reset email has been sent. '
          'Please check your inbox and spam folder.',
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
      ),
    );
  }

  void _showReliabilityDetailModal(BuildContext context, UserProfile profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                PickupReliabilityCard(summary: profile.pickupReliability),
                const SizedBox(height: 20),
                Text(
                  'About Pickup Reliability',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'CampusBite tracks your pickup history to ensure food prepared by cafeterias is collected promptly and food waste is minimized. '
                  'Your status updates automatically as you complete orders.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(modalContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF168039),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color sectionBgColor = Color(0xFFF7F7F9);
    const Color brandGreen = Color(0xFF168039);
    final currentUser = _authService.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: currentUser != null
              ? FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUser.uid)
                    .snapshots()
              : null,
          builder: (context, snapshot) {
            UserProfile userProfile;
            if (snapshot.hasData && snapshot.data!.exists) {
              userProfile = UserProfile.fromFirestore(
                currentUser?.uid ?? '',
                snapshot.data!.data(),
              );
            } else {
              userProfile = UserProfile(
                id: currentUser?.uid ?? '',
                fullName: currentUser?.displayName ?? 'Student',
                email: currentUser?.email ?? '',
              );
            }

            final displayName = userProfile.fullName.isNotEmpty
                ? userProfile.fullName
                : (currentUser?.displayName ?? 'Student');
            final displayEmail = userProfile.email.isNotEmpty
                ? userProfile.email
                : (currentUser?.email ?? 'No email found');
            final statusLabel = userProfile.pickupReliability != null
                ? PickupReliabilityCard.getStatusLabel(
                    userProfile.pickupReliability!.status,
                  )
                : 'New record';

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Section
                  Container(
                    width: double.infinity,
                    color: sectionBgColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      children: [
                        // Top Bar with Back Button & Title
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.black87,
                              ),
                              onPressed: () => Navigator.maybePop(context),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 16),
                            const Text(
                              'My Profile',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Profile Avatar with Edit Badge
                        Center(
                          child: Stack(
                            children: [
                              UserInitialsAvatar(
                                initials: initialsFromName(displayName),
                                color: avatarColorFromName(displayName),
                                size: 84,
                              ),
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF212121),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.edit,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // User Name
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),

                  // Personal Info Section
                  _buildSectionHeader('Personal info'),

                  _buildSettingTile(
                    title: 'Profile Picture',
                    subtitle: 'Update or change avatar',
                    onTap: () {},
                  ),
                  _buildDivider(),
                  _buildSettingTile(
                    title: 'Name',
                    subtitle: displayName,
                    onTap: () {},
                  ),
                  _buildDivider(),
                  _buildSettingTile(
                    title: 'Phone number',
                    subtitle: 'Add your phone number',
                    onTap: () {},
                  ),
                  _buildDivider(),
                  _buildSettingTile(
                    title: 'Email',
                    subtitle: displayEmail,
                    subtitleColor: brandGreen,
                    trailingIcon: Icons.check_circle_outline,
                    trailingIconColor: Colors.black87,
                    onTap: () {},
                  ),

                  // Section Separator
                  _buildSectionGap(),

                  // Pickup Reliability Status Tile Section
                  _buildSectionHeader('Pickup Reliability'),
                  _buildSettingTile(
                    title: 'Reliability Status',
                    subtitle: statusLabel,
                    subtitleColor: PickupReliabilityCard.getStatusColor(
                      userProfile.pickupReliability?.status ??
                          PickupReliabilityStatus.newUser,
                    ),
                    trailingIcon: Icons.chevron_right,
                    onTap: () =>
                        _showReliabilityDetailModal(context, userProfile),
                  ),

                  // Section Separator
                  _buildSectionGap(),

                  // Security Section
                  _buildSectionHeader('Security'),
                  _buildSettingTile(
                    title: 'Password',
                    subtitle: 'Reset password via email verification',
                    onTap: () => _handleResetPassword(context, displayEmail),
                  ),

                  // Section Separator
                  _buildSectionGap(),

                  // Sign Out Section
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    child: InkWell(
                      onTap: () => _handleLogout(context),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        child: Text(
                          'Sign out',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE53935),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? subtitleColor,
    IconData trailingIcon = Icons.chevron_right,
    Color trailingIconColor = Colors.black87,
  }) {
    return Container(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: subtitleColor ?? Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(trailingIcon, color: trailingIconColor, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.grey.shade100,
      indent: 16,
    );
  }

  Widget _buildSectionGap() {
    return Container(
      height: 12,
      width: double.infinity,
      color: const Color(0xFFF7F7F9),
    );
  }
}
