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
            'Terms and Conditions\n\n'
            '1. Acceptance of Terms\n'
            'By accessing or using this application, you agree to be bound by these terms and conditions.\n\n'
            '2. Use of the Application\n'
            'You agree to use the application only for lawful purposes and in accordance with these terms.\n\n'
            '3. Intellectual Property\n'
            'All content, features, and functionality of the application are the exclusive property of the application owner.\n\n'
            '4. Limitation of Liability\n'
            'The application owner shall not be liable for any damages arising from the use of the application.\n\n'
            '5. Changes to Terms\n'
            'The application owner reserves the right to modify these terms at any time without prior notice.\n\n'
            '6. Governing Law\n'
            'These terms shall be governed by and construed in accordance with the laws of the jurisdiction in which the application owner operates.',
          ),
        ),
      ),
    );
  }
}
