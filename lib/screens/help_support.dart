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
              onTap: () => context.push('/support/faq'),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Contact us'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/support/contact'),
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
            title: Text('About delivery?'),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'We currently DO NOT deliver to any location. the app is a self pick based, users order food and the cafe receives orders to process them and prepare once ready(completed), users go to the corresponding cafe and pick their meals.',
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('About payment?'),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'The app is strictly non payment proccessing, it DOES NOT accept, process or make payments. We encourage users to only pay at the cafe in which they ordered their meals',
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('What happens my account is suspended?'),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'If you accidentally did not take your food and ended up suspended consider appealing to the cafe admins.',
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
              title: Text('Campus Cafe admins'),
              subtitle: Text('Cafe 1 or 2, at universitie\'s main campus'),
            ),
          ],
        ),
      ),
    );
  }
}
