import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../widgets/logout_confirmation_dialog.dart';

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
                Text(
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

                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data = snapshot.data!.data();
                      if (data != null) {
                        final fullName = data['fullName'] as String? ?? '';
                        if (fullName.isNotEmpty) {
                          displayName = fullName.split(' ').first;
                        }
                        displayEmail = data['email'] as String? ?? displayEmail;
                      }
                    } else {
                      // Fallback to FirebaseAuth user properties if snapshot not ready/doesn't exist
                      if (user?.displayName != null &&
                          user!.displayName!.isNotEmpty) {
                        displayName = user.displayName!.split(' ').first;
                      }
                    }

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(50),
                              child: Image.asset(
                                'designs/assets/avatar.jpg',
                                height: 70.0,
                                width: 70,
                              ),
                            ),
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
                                Text(
                                  displayEmail,
                                  style: const TextStyle(fontSize: 13),
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
                onTap: () {},
              ),

              const Divider(height: 1),

              _settingTile(
                icon: Icons.help_outline,
                iconColor: Colors.grey.shade700,
                background: Colors.grey.shade200,
                title: 'Help & Support',
                subtitle: 'FAQs and customer support',
                onTap: () => context.go('/support'),
              ),

              const Divider(height: 1),

              _settingTile(
                icon: Icons.privacy_tip_outlined,
                iconColor: Colors.grey.shade700,
                background: Colors.grey.shade200,
                title: 'Terms & Privacy',
                subtitle: 'Policies and usage guidelines',
                onTap: () => context.go('/terms'),
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

// notification screen
class Notify extends StatelessWidget {
  const Notify({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
