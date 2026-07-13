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

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms and Conditions')),
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Text(
                '''
Last Updated: Sept 9, 2026

Welcome to Campus Bite
These Terms govern your use of the Campus Bite
 mobile application. By accessing or using our App Campus Bite or website at foodapp.larason.space, you agree to be bound by these terms.

1. Eligibility and Account Registration
• Target Audience: The App is intended primarily for university students, faculty, and staff.
• Account Creation: You must provide accurate, current, and complete information (e.g., university email) during registration(We respect your confidentiality).
• Account Security: You are responsible for safeguarding your password and for all activities under your account.

2. Strict Collection Policy (No Food Waste)
• In alignment with cafeteria administrative guidelines, uncollected food represents material loss. Users agree to collect their food within given notified time calculated by their current distance from the cafe, after receiving the "Ready for Collection" status. Abandoned bookings will result in immediate suspension.

3. Ordering and Payments
• Placing Orders: Orders made through the App are subject to acceptance by the vendor.
• Pricing: Prices include food, taxes, delivery fees, and platform fees displayed at the app. Prices may change without notice.
• Allergies: Campus Bite is a platform and cannot guarantee food is free of allergens. You must communicate severe dietary restrictions directly to the vendor.

4. Delivery and Pick-up
• Currently we do not offer any delivery services, This is a self pick based app.
• Delivery Times: Estimated delivery times are provided for convenience and are not guaranteed.

5. Cancellations and Refunds
• Cancellations: Orders cannot be cancelled by you when you press the "Place order & notify cafe" button.
• Refund Policy: Incorrect or missing items must be reported within 2 hours of delivery for a case-by-case review.

6. User Conduct
You agree to use the application only for lawful purposes. You agree not to place fake orders, harass vendors, or attempt to hack the App's security.

7. Account Penalty System
To ensure a reliable service for everyone, the App tracks your order collection behavior using a percentage-based status system:
• 0% (Good Standing): Your account is safe and operating normally.
• Penalty Increases (up to 50%): Failing to pick up your ordered food increases your penalty percentage. Reaching 50% serves as a critical warning.
• 100% (Ordering Restricted): If your penalty status reaches 100% due to repeated uncollected food, your ability to place new orders will be disabled. You will still be able to log in, browse the App, and view menus, but you cannot check out.
• Restoring Order Privileges: To remove the ordering restriction after reaching 100%, you must contact the App Administrator directly to appeal.

8. Intellectual Property
All content, features, and functionality of the application are the exclusive property of the application owner(s). Refer the License.

9. Limitation of Liability
The application owner(s) shall not be liable for any damages arising from the use of the application, including issues regarding the quality or safety of the food prepared by third-party vendors.

10. Changes to Terms
The application owner reserves the right to modify these terms at any time. Continued use after changes constitutes your acceptance.

11. Governing Law
These terms shall be governed by and construed in accordance with the laws of the jurisdiction in which the application owner(s) operates.

12. Contact Us
For support, see the Help & support page or email directly lembotor6@gmail.com''',
                style: TextStyle(
                  fontSize: 14.0,
                  height: 1.5,
                  color: Colors.black,
                  fontWeight: FontWeight
                      .normal, // Adds a little line spacing for better readability
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Failure to adhere to these rules can disrupt cafeteria efficiency and lead to account bans.',
                style: TextStyle(
                  fontSize: 14.0,
                  height: 1.5,
                  color: Colors.red,
                  fontWeight: FontWeight
                      .bold, // Adds a little line spacing for better readability
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
