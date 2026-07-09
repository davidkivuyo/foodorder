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
          child: Text(
            '''Terms and Conditions

Last Updated: Sept 9, 2026

Welcome to Campus Bite
! These Terms govern your use of the Campus Bite
 mobile application. By accessing or using our App, you agree to be bound by these terms.

1. Eligibility and Account Registration
• User will lose access to their account once they do not collect their orders for 2 consecutive times and their strikes points fall to 0 points.
• Target Audience: The App is intended primarily for university students, faculty, and staff.
• Account Creation: You must provide accurate, current, and complete information (e.g., university email, campus delivery location) during registration.
• Account Security: You are responsible for safeguarding your password and for all activities under your account.

2. Ordering and Payments
• Placing Orders: Orders made through the App are subject to acceptance by the vendor.
• Pricing: Prices include food, taxes, delivery fees, and platform fees displayed at checkout. Prices may change without notice.
• Allergies: Campus Bite
 is a platform and cannot guarantee food is free of allergens. You must communicate severe dietary restrictions directly to the vendor.

3. Delivery and Pick-up
• Campus Zones: Deliveries are restricted to specific designated campus areas (e.g., dorms, library entrances).
• Delivery Times: Estimated delivery times are provided for convenience and are not guaranteed.
• Unreachable Customers: If a driver cannot reach you at the designated location within 10 minutes, the food may be left or discarded. You will still be charged.

4. Cancellations and Refunds
• Cancellations by You: Orders can only be cancelled for a full refund before the vendor begins preparation.
• Refund Policy: Incorrect or missing items must be reported within 2 hours of delivery for a case-by-case review.

5. User Conduct
You agree to use the application only for lawful purposes. You agree not to place fake orders, harass delivery drivers, or attempt to hack the App's security.

6. Intellectual Property
All content, features, and functionality of the application are the exclusive property of the application owner[cite: 1].

7. Limitation of Liability
The application owner shall not be liable for any damages arising from the use of the application[cite: 1], including issues regarding the quality or safety of the food prepared by third-party vendors.

8. Changes to Terms
The application owner reserves the right to modify these terms at any time[cite: 1]. Continued use after changes constitutes your acceptance.

9. Governing Law
These terms shall be governed by and construed in accordance with the laws of the jurisdiction in which the application owner operates[cite: 1].

10. Contact Us
For support, contact us at [Support Email Address] or [Support Phone Number].''',
            style: TextStyle(
              fontSize: 14.0,
              height: 1.5,
              color: Colors.black,
              fontWeight: FontWeight
                  .normal, // Adds a little line spacing for better readability
            ),
          ),
        ),
      ),
    );
  }
}
