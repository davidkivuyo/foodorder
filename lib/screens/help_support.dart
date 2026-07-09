import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help and support')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const Text(
              'How can we help?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Frequently Asked Questions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/support/faq'),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Contact us'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/support/contact'),
            ),
          ],
        ),
      ),
    );
  }
}

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FAQ')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: const [
          ExpansionTile(
            title: Text('Where do you deliver on campus?'),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'We currently deliver to all main dorms, the central library, and the student union building. Please ensure you select a valid drop-off zone at checkout.',
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('Can I pay with my Student Meal Plan?'),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Yes! You can link your student ID in the account settings to pay using your meal plan or campus dining dollars.',
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('What if my order is missing an item?'),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Please reach out through our Contact Us page within 2 hours of delivery, and we will review your order for a refund or credit.',
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('What happens if I miss my delivery driver?'),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Drivers will wait for 10 minutes at the designated drop-off zone. If they cannot reach you, the food may be left at the location or discarded, and you will still be charged.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact us')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Get in Touch',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Have a problem with your order or a suggestion for Campus Bite? Let us know!',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.email, color: Colors.blue),
              title: const Text('Email Support'),
              subtitle: const Text('lembotor6@gmail.com'),
              onTap: () {
                // Add functionality to open default email app
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.phone, color: Colors.green),
              title: const Text('Call Us'),
              subtitle: const Text('**********'),
              onTap: () {
                // Add functionality to open phone dialer
              },
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.location_on, color: Colors.red),
              title: Text('Campus Office'),
              subtitle: Text('Student Union, Room 104\nMon-Fri, 9 AM - 5 PM'),
            ),
          ],
        ),
      ),
    );
  }
}
