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
import '../utils/responsive.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms and Conditions')),
      body: desktopCentered(
        context,
        const Padding(
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

2. Pickup & Collection Policy (Reducing Food Waste)
• In alignment with cafeteria administrative guidelines, uncollected food represents material loss. Users agree to collect their food within the notified pickup window, calculated from their current distance to the cafe, after receiving the "Ready for Collection" status.
• If an order is not collected by the end of the pickup window and grace period, it is recorded as a no-show and you are notified. Missing a pickup is not a suspension or penalty: your pickup reliability is informational only.

3. Data privacy and Protection.
• The app will request your device location While Using App location permission only after you press “Place Order”. This is used only to calculate the distance between the cafe and the user.
• CampusBite uses your location once per order to estimate the pickup time. It doesnot store the location but rather the distance between the device and the cafe needed for that order and does not track your movement or maintain any kind of location data or history.
• This data will be used to calculate the estimated time for pickup when order is ready to be fair and avoid delays. Consider making sure your phone has the correct time settings to reduce inaccuracies.
• If you ever want to redact your data and information, no need to worry just contact the support team. We care your privacy.

4. Ordering and Payments
• Placing Orders: Orders made through the App are subject to acceptance by the vendor.
• Pricing: Prices include food, taxes, delivery fees, and platform fees displayed at the app. Prices may change without notice.
• Allergies: Campus Bite is a digital platform and cannot guarantee food is free of allergens. You must communicate severe dietary restrictions directly to the vendor.

5. Delivery and Pick-up
• Currently we do not offer any delivery services, This is a self pick based app.
• Food preparation Times: Estimated preparation times are provided for convenience and are not guaranteed.

6. Cancellations and Refunds
• Cancellations: You may cancel an order within 2 minutes of placing it, before the cafe accepts it. After the cancellation window expires, orders cannot be cancelled by you.
• Refund Policy: Refund is subject to the corresponding ordered cafes rules.

7. User Conduct
You agree to use the application only for lawful purposes. You agree not to place fake orders, harass vendors, or attempt to hack the App's security.

8. Pickup Reliability
To help reduce food waste, the App measures how consistently you collect your orders on time and shows the result in your profile as a pickup reliability score:
• Reliability is informational only. It does not restrict ordering, suspend your account, or impose penalties.
• New users and users with limited history see a neutral "building your record" state — never a poor rating.
• You can always view your own reliability; other users' reliability is never shown to you.

9. Intellectual Property
All content, features, and functionality of the application are the exclusive property of the application owner(s). Refer the License.

10. Limitation of Liability
The application owner(s) shall not be liable for any damages arising from the use of the application, including issues regarding the quality or safety of the food prepared by third-party vendors.

11. Changes to Terms
The application owner reserves the right to modify these terms at any time. Continued use after changes constitutes your acceptance.

12. Governing Law
These terms shall be governed by and construed in accordance with the laws of the jurisdiction in which the application owner(s) operates.

13. Contact Us
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
                  'Please collect your orders within the pickup window to help keep cafeterias efficient and reduce food waste.',
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
      ),
    );
  }
}
