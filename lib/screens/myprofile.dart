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
import 'package:campusbite/services/app_log.dart';
import 'package:campusbite/services/firestore_profile_service.dart';
import 'package:campusbite/services/input_validator.dart';
import 'package:campusbite/widgets/pickup_reliability_card.dart';
import 'package:campusbite/widgets/restriction_notice.dart';
import 'package:campusbite/widgets/user_initials_avatar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/logout_confirmation_dialog.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  static final _authService = AuthService();
  static final _firestoreProfileService = FirestoreProfileService();

  // Edit mode state
  bool _isEditing = false;
  final _nameController = TextEditingController();
  String? _errorMessage;
  bool _isSaving = false;

  // Current profile values (updated by StreamBuilder, used to seed controllers)
  String _currentFullName = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Logout
  // -------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // Password reset
  // -------------------------------------------------------------------------

  void _handleResetPassword(BuildContext context) async {
    // Always reset using the canonical FirebaseAuth email — never the
    // Firestore copy (which can be stale) and never the 'No email found'
    // display placeholder. AuthService.sendPasswordReset deliberately
    // returns null even on invalid-email/user-not-found (anti-enumeration),
    // so the UI must validate before sending.
    final email = _authService.currentUser?.email?.trim() ?? '';
    if (!InputValidator.isValidEmail(email)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset is unavailable because no valid email address '
            'is linked to your account.',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

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

  // -------------------------------------------------------------------------
  // Profile save
  // -------------------------------------------------------------------------

  Future<void> _saveProfile() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      setState(() {
        _isSaving = false;
      });
      return;
    }

    // Sanitize and validate name
    final rawName = _nameController.text.trim();
    final sanitizedName = InputValidator.sanitizeName(rawName);
    if (sanitizedName.isEmpty) {
      setState(() {
        _isSaving = false;
        _errorMessage = 'Name is invalid. Please enter a valid name.';
      });
      return;
    }

    // Email is immutable and can never be edited. Only the name changes here;
    // the Firestore email is kept in sync with the authenticated account email.
    try {
      await _firestoreProfileService
          .updateProfile(
            userId: currentUser.uid,
            fullName: sanitizedName,
            email: currentUser.email ?? '',
          )
          // Bound the write so an offline/pending Future cannot hang the
          // save flow indefinitely; on timeout the catch below resets
          // _isSaving and invites a retry.
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully.'),
          backgroundColor: Color(0xFF168039),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Exception catch (e) {
      AppLog.e('[MyProfileScreen] _saveProfile error', e);
      setState(() {
        _isSaving = false;
        _errorMessage = 'Failed to update profile. Please try again.';
      });
    }
  }

  // -------------------------------------------------------------------------
  // Widget build
  // -------------------------------------------------------------------------

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

            // Store for use by edit-mode controllers
            _currentFullName = displayName;
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
                                color: Colors.black,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Profile Avatar
                        Center(
                          child: UserInitialsAvatar(
                            initials: initialsFromName(displayName),
                            color: avatarColorFromName(displayName),
                            size: 84,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // User Name - editable or display
                        _isEditing
                            ? TextField(
                                controller: _nameController,
                                autofocus: false,
                                decoration: const InputDecoration(
                                  hintText: 'Full name',
                                  border: UnderlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                              )
                            : Text(
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

                  _buildProfileEditTile(
                    title: 'Name',
                    subtitle: _isEditing
                        ? _nameController.text.isNotEmpty
                            ? _nameController.text
                            : displayName
                        : displayName,
                    onTap: _onEditingTap,
                  ),
                  _buildDivider(),
                  // Email is immutable — display only, never editable.
                  _buildSettingTile(
                    title: 'Email',
                    subtitle: displayEmail,
                    subtitleColor: brandGreen,
                    trailingIcon: Icons.check_circle_outline,
                    trailingIconColor: Colors.black87,
                  ),

                  // Save / Cancel buttons when in edit mode
                  if (_isEditing) ...[
                    _buildSectionGap(),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: _isSaving
                                  ? null
                                  : () {
                                      setState(() {
                                        _isEditing = false;
                                        _nameController.clear();
                                      });
                                    },
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _saveProfile,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF168039),
                                foregroundColor: Colors.white,
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildSectionGap(),
                  ], // if _isEditing

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

                  // Phase E §16 — ordering-limit notice (derived from the
                  // already-loaded server-maintained summary; no new query).
                  if (userProfile.pickupReliability != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: RestrictionNotice(
                        level: userProfile.pickupReliability!.restrictionLevel,
                        activeOrderLimit:
                            userProfile.pickupReliability!.activeOrderLimit,
                      ),
                    ),
                  ],

                  // Section Separator
                  _buildSectionGap(),

                  // Security Section
                  _buildSectionHeader('Security'),
                  _buildSettingTile(
                    title: 'Password',
                    subtitle: 'Reset password via email verification',
                    onTap: () => _handleResetPassword(context),
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

  // -------------------------------------------------------------------------
  // Helper methods
  // -------------------------------------------------------------------------

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
    VoidCallback? onTap,
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

  // Tapping the name label when not editing does nothing;
  // the save/cancel buttons handle the flow.
  void _onEditingTap() {
    if (_isEditing) return;
    _nameController.text = _currentFullName;
    setState(() => _isEditing = true);
  }

  Widget _buildProfileEditTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? subtitleColor,
    IconData trailingIcon = Icons.chevron_right,
    Color trailingIconColor = Colors.black87,
  }) {
    return _buildSettingTile(
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      subtitleColor: subtitleColor,
      trailingIcon: trailingIcon,
      trailingIconColor: trailingIconColor,
    );
  }

  void _showReliabilityDetailModal(BuildContext context, UserProfile profile) {
    final reliability = profile.pickupReliability;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Text(
                      'Pickup Reliability',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (reliability != null)
                      PickupReliabilityCard(summary: reliability)
                    else
                      const Text(
                        'No reliability data yet. Your record will appear after your first order.',
                        style: TextStyle(color: Colors.grey),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}