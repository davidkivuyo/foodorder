import 'package:flutter/material.dart';
import 'navigation/bottom_navigation.dart';
// import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(MyApp());
}

// The main widget
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Food order app',
    theme: ThemeData(
    useMaterial3: true,
    colorSchemeSeed: Colors.blue,
    // Define the global typography theme
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold, color: Colors.black),
      bodyMedium: TextStyle(fontSize: 14.0, color: Colors.grey),
    ),
  ),
      home: const MainScreen(),
    );
  }
}

