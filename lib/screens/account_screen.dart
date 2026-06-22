import 'package:flutter/material.dart';


//about screen
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Account'));
  }
}

// notification screen
class Notify extends StatelessWidget {
  const Notify({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications'),
        backgroundColor: const Color.fromARGB(255, 230, 230, 230),
        ),
        );
  }
}
