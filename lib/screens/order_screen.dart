import 'package:flutter/material.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My orders',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: .75,
                ),
              ),
              OrderCards(),
              const SizedBox(height: 10),

              OrderCards1(),
            ],
          ),
        ),
      ),
    );
  }
}

class OrderCards extends StatefulWidget {
  const OrderCards({super.key});
  @override
  State<OrderCards> createState() => _OrderCardsState();
}

class _OrderCardsState extends State<OrderCards> {
  @override
  Widget build(BuildContext context) {
    return Card(
      // elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order #CB-8234', style: TextStyle(fontSize: 12)),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '⏱️ Preparing',
                    style: TextStyle(
                      color: Colors.brown[900],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'The burger joint',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1x Classic cheeseburger combo',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w200),
                ),
                Text(
                  '1x Vanilla milkshake',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w200),
                ),
              ],
            ),
            Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tsh10000',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[900],
                  ),
                ),
                TextButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all<Color>(
                      Colors.brown,
                    ),
                  ),
                  onPressed: () {},
                  child: Text(
                    'TextButton',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class OrderCards1 extends StatefulWidget {
  const OrderCards1({super.key});
  @override
  State<OrderCards1> createState() => _OrderCards1State();
}

class _OrderCards1State extends State<OrderCards1> {
  @override
  Widget build(BuildContext context) {
    return Card(
      //elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order #CB-8289', style: TextStyle(fontSize: 12)),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '🧺Ready',
                    style: TextStyle(
                      color: Colors.green[800],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'Pilau nyama',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1x Green vegetables',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w200),
                ),
                Text(
                  '1x Vanilla milkshake',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w200),
                ),
              ],
            ),
            Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tsh10000',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[900],
                  ),
                ),
                TextButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all<Color>(
                      Colors.green,
                    ),
                  ),
                  onPressed: () {},
                  child: Text(
                    'show code',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
