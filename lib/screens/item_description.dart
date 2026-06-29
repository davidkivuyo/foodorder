import 'package:flutter/material.dart';
import '../data/food_data.dart';

class ItemDescriptions extends StatelessWidget {
  final FoodItem item;

  const ItemDescriptions({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: Hero(
        tag: item.image,
        child: Image.asset(
          item.image,
          height: 100,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
