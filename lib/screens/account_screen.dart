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

import 'package:campusbite/screens/myprofile.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_service.dart';
import '../widgets/user_initials_avatar.dart';
import 'diagnostics_screen.dart';
import 'notification_screen.dart';

export 'notification_screen.dart' show NotificationScreen;



//account screen
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  /// Version string loaded from the app package, e.g. "1.2.3".
  /// Null while loading; shown as a dash to avoid layout jumps.
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = info.version);
      }
    } on Exception catch (_) {
      // Graceful degradation: leave _appVersion null; UI shows a dash.
    }
  }

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
                const Text(
                  "What's your bite today?",
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
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
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            UserInitialsAvatar(
                              initials: initialsFromName(rawFullName),
                              color: avatarColorFromName(rawFullName),
                              size: 70,
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
                        // Dynamically reflects the git tag used at release
                        // (injected via --build-name in the CI workflow).
                        'Campus Bite v${_appVersion ?? '-'}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      const Text(
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



class AccountSettings extends StatelessWidget {
  const AccountSettings({super.key});

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
              _settingTile(
                icon: Icons.edit_outlined,
                iconColor: Colors.green,
                background: Colors.green.shade50,
                title: 'My Profile',
                subtitle: 'Manage your profile info',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyProfileScreen()),
                  );
                },
              ),
              const Divider(height: 1, thickness: 0.5),
              /*_settingTile(
                icon: Icons.receipt_long_outlined,
                iconColor: Colors.blue,
                background: Colors.blue.shade50,
                title: 'Order History',
                subtitle: 'View your previous orders',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OrdersScreen()),
                  );
                },
              ),

              const Divider(height: 1), */
              _settingTile(
                icon: Icons.help_outline,
                iconColor: Colors.grey.shade700,
                background: Colors.grey.shade200,
                title: 'Help & Support',
                subtitle: 'FAQs and customer support',
                onTap: () => context.push('/support'),
              ),

              const Divider(height: 1, thickness: 0.5),

              _settingTile(
                icon: Icons.privacy_tip_outlined,
                iconColor: Colors.grey.shade700,
                background: Colors.grey.shade200,
                title: 'Terms & Privacy',
                subtitle: 'Policies and usage guidelines',
                onTap: () => context.push('/terms'),
              ),

              const Divider(height: 1, thickness: 0.5),

              // Phase 17 — hidden diagnostics entry (debug builds or admins).
              const DiagnosticsEntryTile(),
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
