import 'package:campusbite/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'register_screen.dart';

//account screen
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    String name = 'Donny wilson';
    String email = 'donny.wilson@student.udsm.ac.tz';
    String id = '2025-04-04170';
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
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(10),
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
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.email_outlined, size: 15),
                            SizedBox(width: 5),
                            Text(email, style: TextStyle(fontSize: 13)),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.perm_identity, size: 15),
                            SizedBox(width: 5),
                            Text(id, style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                AccountSettings(),

                const SizedBox(height: 18),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Campus Bite v1.0.0 (stable)',
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
                title: 'Edit Profile',
                subtitle: 'Manage your personal information',
                onTap: () {},
              ),

              const Divider(height: 1),

              _settingTile(
                icon: Icons.notifications_none,
                iconColor: Colors.orange,
                background: Colors.orange.shade50,
                title: 'Notification Settings',
                subtitle: 'Alerts, order updates and promos',
                onTap: () {},
              ),

              const Divider(height: 1),

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
                onTap: () {},
              ),

              const Divider(height: 1),

              _settingTile(
                icon: Icons.privacy_tip_outlined,
                iconColor: Colors.grey.shade700,
                background: Colors.grey.shade200,
                title: 'Terms & Privacy',
                subtitle: 'Policies and usage guidelines',
                onTap: () {},
              ),

              const Divider(height: 1),

              _settingTile(
                icon: Icons.logout,
                iconColor: Colors.red,
                background: Colors.red.shade50,
                title: 'Logout',
                subtitle: 'Securely exit your account',
                titleColor: Colors.red,
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.account_circle,
                iconColor: Colors.grey,
                background: Colors.grey.shade200,
                title: 'register',
                subtitle: 'register',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => RegisterScreen()),
                  );
                },
              ),
              _settingTile(
                icon: Icons.login,
                iconColor: Colors.grey.shade700,
                background: Colors.grey.shade200,
                title: 'Login',
                subtitle: 'login back to your account',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => LoginScreen()),
                  );
                },
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
