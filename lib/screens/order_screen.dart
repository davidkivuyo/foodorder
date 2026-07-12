import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/order.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String? _userId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _ordersStream;

  @override
  void initState() {
    super.initState();
    _setupStream();
  }

  void _setupStream() {
    _userId = FirebaseAuth.instance.currentUser?.uid;
    if (_userId != null) {
      _ordersStream = FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: _userId)
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _userId == null
          ? const Center(child: Text('Please sign in to view orders'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _ordersStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_off,
                              size: 50, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'Could not load orders',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            style: const TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                // Parse orders from Firestore
                final orders = (snapshot.data?.docs ?? [])
                    .map((doc) {
                      try {
                        return FoodOrder.fromFirestore(doc);
                      } catch (e) {
                        debugPrint(
                          '[OrdersScreen] Error parsing order ${doc.id}: $e',
                        );
                        return null;
                      }
                    })
                    .whereType<FoodOrder>()
                    .toList();

                // Sort: newest first
                orders.sort((a, b) => b.orderTime.compareTo(a.orderTime));

                // Separate into active and completed
                final activeOrders = orders.where(
                  (o) =>
                      o.status == OrderStatus.pending ||
                      o.status == OrderStatus.accepted ||
                      o.status == OrderStatus.preparing ||
                      o.status == OrderStatus.ready,
                ).toList();

                final completedOrders = orders.where(
                  (o) =>
                      o.status == OrderStatus.collected ||
                      o.status == OrderStatus.rejected ||
                      o.status == OrderStatus.noShow,
                ).toList();

                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.receipt_long_outlined,
                            size: 50,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'No orders yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Place your first order and track it here',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'My Orders',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: .75,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${orders.length} order${orders.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Active orders section
                        if (activeOrders.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Active Orders',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...activeOrders.map(
                            (order) =>
                                _buildOrderCard(context, order),
                          ),
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 12),
                        ],

                        // Completed orders section
                        if (completedOrders.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Completed Orders',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...completedOrders.map(
                            (order) =>
                                _buildOrderCard(context, order),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  ({
    Color color,
    String icon,
    String label,
  }) _statusVisuals(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return (
          color: Colors.orange,
          icon: '⏳',
          label: 'Pending',
        );
      case OrderStatus.accepted:
        return (
          color: Colors.blue[700]!,
          icon: '✅',
          label: 'Accepted',
        );
      case OrderStatus.rejected:
        return (
          color: Colors.red[700]!,
          icon: '❌',
          label: 'Rejected',
        );
      case OrderStatus.preparing:
        return (
          color: Colors.brown[900]!,
          icon: '⏱️',
          label: 'Preparing',
        );
      case OrderStatus.ready:
        return (
          color: Colors.green[800]!,
          icon: '⚡',
          label: 'Ready',
        );
      case OrderStatus.collected:
        return (
          color: Colors.grey[700]!,
          icon: '✅',
          label: 'Collected',
        );
      case OrderStatus.noShow:
        return (
          color: Colors.red[900]!,
          icon: '🚫',
          label: 'No Show',
        );
    }
  }

  Widget _buildOrderCard(BuildContext context, FoodOrder order) {
    final visuals = _statusVisuals(order.status);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order ID and Status badge
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
                    '${visuals.icon} ${visuals.label}',
                    style: TextStyle(
                      color: visuals.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Cafe name if available
            if (order.items.isNotEmpty &&
                order.items.first.displayCafe.isNotEmpty)
              Text(
                'Cafe ${order.items.first.displayCafe}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            const SizedBox(height: 4),

            // Order items
            ...order.items.map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${item.quantity}x ${item.foodItem.title}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                    Text(
                      'Tsh ${(item.foodItem.price * item.quantity).toInt()}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Divider(),

            // Total and order time
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
                Text(
                  _formatOrderTime(order.orderTime),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatOrderTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
