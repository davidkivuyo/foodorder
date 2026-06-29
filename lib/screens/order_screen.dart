import 'package:flutter/material.dart';
import '../services/cart_service.dart';
import '../models/order.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  Widget _buildDynamicOrderCard(BuildContext context, FoodOrder order) {
    Color statusColor;
    String statusText;
    switch (order.status) {
      case OrderStatus.preparing:
        statusColor = Colors.brown[900]!;
        statusText = '⏱️ Preparing';
        break;
      case OrderStatus.ready:
        statusColor = Colors.green[800]!;
        statusText = '⚡ Ready';
        break;
      case OrderStatus.collected:
        statusColor = Colors.grey[700]!;
        statusText = '✅ Collected';
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order #${order.orderId}',
                  style: const TextStyle(fontSize: 12),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              order.items.isNotEmpty
                  ? order.items.first.foodItem.title
                  : 'Food Order',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: order.items.map((item) {
                return Text(
                  '${item.quantity}x ${item.foodItem.title}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                  ),
                );
              }).toList(),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tsh ${order.totalAmount.toInt()}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[900],
                  ),
                ),
                if (order.status == OrderStatus.ready)
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.green[900],
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed: () {
                      CartService().simulateAdminStatusChange(
                        order.orderId,
                        OrderStatus.collected,
                      );
                    },
                    child: const Text(
                      'Confirm Collected',
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                else if (order.status == OrderStatus.preparing)
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.orange[800],
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () {
                      CartService().simulateAdminStatusChange(
                        order.orderId,
                        OrderStatus.ready,
                      );
                    },
                    child: const Text(
                      'Simulate Cafe Ready',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  )
                else
                  Text(
                    'Order Completed',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartService = CartService();

    return Scaffold(
      body: ListenableBuilder(
        listenable: cartService,
        builder: (context, child) {
          final activeOrders = cartService.orders;

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My orders',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: .75,
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (activeOrders.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Active Orders (Real-time)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    ...activeOrders.map(
                      (order) => _buildDynamicOrderCard(context, order),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                  ],

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'Past / Demo Orders',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const OrderCards(),
                  const SizedBox(height: 10),
                  const OrderCards1(),
                  const SizedBox(height: 10),
                  const OrderHistory(),
                ],
              ),
            ),
          );
        },
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),

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
              'Chips burger',
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
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.brown[700],
                  ),
                  onPressed: () {},
                  child: Text(
                    'Track Order',
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),

                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '⚡Ready',
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
                  '1x salad',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w200),
                ),
              ],
            ),
            Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tsh2500',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[900],
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.green[900],
                  ),
                  onPressed: () {},
                  child: Text(
                    'show QR code',
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

class OrderHistory extends StatefulWidget {
  const OrderHistory({super.key});
  @override
  State<OrderHistory> createState() => _OrderHistoryState();
}

class _OrderHistoryState extends State<OrderHistory> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Order History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: () {},
              icon: Icon(Icons.arrow_forward),
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                iconSize:
                    19, // Shrinks the background wrapper tight around the icon
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // History Card 1: Campus Pizza
        _buildHistoryCard(
          imagePath:
              'designs/assets/juice.jpg', // Replace with your pizza image path
          title: 'Big juice',
          price: 'Tsh1000',
          date: 'Oct 24',
        ),
        const SizedBox(height: 12),

        // History Card 2: The Study Grind
        _buildHistoryCard(
          imagePath:
              'designs/assets/chipskavu.jpg', // Replace with your coffee image path
          title: 'The Study Grind',
          price: 'Tsh2500',
          date: 'Oct 22',
        ),
      ],
    );
  }

  Widget _buildHistoryCard({
    required String imagePath,
    required String title,
    required String price,
    required String date,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Food Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              imagePath,
              height: 60,
              width: 60,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),

          // 2. Center Content (Title, Subtitle, Price)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      date,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),

                const SizedBox(height: 6),
                Text(
                  price,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
