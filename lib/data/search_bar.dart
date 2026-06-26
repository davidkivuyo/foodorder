import 'package:flutter/material.dart';

class SearchBarScreen extends StatelessWidget {
  const SearchBarScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          height: 20,
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search your next meal',
              hintStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              border: InputBorder.none,
            ),
          ),
        ),
      ),

      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Divider(),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(),
            ),
          ],
        ),
      ),
    );
  }
}
