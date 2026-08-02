// Copyright 2026 davidkivuyo, johnsonmushi, edwinkessy276-art, jugraki-art.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/order.dart';
import '../models/cart_item.dart';
import '../data/food_data.dart';
import '../services/app_log.dart';
import '../services/cart_service.dart';
import '../services/pickup_deadline_service.dart';
import '../widgets/pickup_countdown.dart';
import '../widgets/cart_bottom_sheet.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  String? _userId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _ordersStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _plannedOrdersStream;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _setupStream();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _setupStream() {
    _userId = FirebaseAuth.instance.currentUser?.uid;
    if (_userId != null) {
      _ordersStream = FirebaseFirestore.instance
          .collection('orders')
          .where('studentId', isEqualTo: _userId)
          .snapshots();

      _plannedOrdersStream = FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('plans')
          .orderBy('plannedDate', descending: false)
          .snapshots();
    }
  }

  /// Reorder all items from a previous order
  Future<void> _handleReorder(FoodOrder order) async {
    final cartService = CartService();
    int addedCount = 0;
    int unavailableCount = 0;

    for (final item in order.items) {
      // Ensure the FoodItem has a non-empty document ID
      final foodItemId = item.foodItem.id.isNotEmpty
          ? item.foodItem.id
          : item.id;
      final targetFoodItem = item.foodItem.id.isNotEmpty
          ? item.foodItem
          : FoodItem(
              id: foodItemId,
              title: item.foodItem.title,
              price: item.foodItem.price,
              image: item.foodItem.image,
              category: item.foodItem.category,
              availableCafes: item.foodItem.availableCafes,
              available: item.foodItem.available,
            );

      if (targetFoodItem.available) {
        for (int i = 0; i < item.quantity; i++) {
          await cartService.addToCart(
            targetFoodItem,
            selectedCafe: item.selectedCafe,
          );
        }
        addedCount += item.quantity;
      } else {
        unavailableCount += item.quantity;
      }
    }

    if (!mounted) return;

    if (addedCount > 0) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reordered $addedCount item${addedCount > 1 ? 's' : ''} to cart!'
            '${unavailableCount > 0 ? " ($unavailableCount item out of stock)" : ""}',
          ),
          backgroundColor: Colors.green.shade800,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'VIEW CART',
            textColor: Colors.white,
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => CartBottomSheet(onOrderPlaced: () {}),
              );
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Items in this order are currently unavailable.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Save an order or custom meal to Planned Orders
  Future<void> _saveToPlannedOrders({
    required String title,
    required List<CartItem> items,
    required DateTime plannedDate,
    String? note,
  }) async {
    if (_userId == null) return;
    try {
      final double total = items.fold(
        0.0,
        (acc, i) => acc + (i.foodItem.price * i.quantity),
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('plans')
          .add({
            'title': title,
            'plannedDate': Timestamp.fromDate(plannedDate),
            'note': note ?? '',
            'totalAmount': total,
            'createdAt': FieldValue.serverTimestamp(),
            'items': items
                .map(
                  (i) => {
                    'foodItemId': i.foodItem.id,
                    'title': i.foodItem.title,
                    'price': i.foodItem.price,
                    'quantity': i.quantity,
                    'image': i.foodItem.image,
                    'selectedCafe': i.selectedCafe,
                    'category': i.foodItem.category,
                    'displayCafe': i.foodItem.displayCafe,
                  },
                )
                .toList(),
          });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "$title" to Planned Meals!'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save plan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Delete a planned meal
  Future<void> _deletePlannedOrder(String docId) async {
    if (_userId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('plans')
          .doc(docId)
          .delete();
    } catch (e) {
      AppLog.e('[OrdersScreen] Delete planned order error', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view orders')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Orders',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.orange,
          labelColor: Colors.orange.shade900,
          unselectedLabelColor: Colors.grey.shade600,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.timer_outlined), text: 'Active'),
            Tab(icon: Icon(Icons.history), text: 'History'),
            Tab(icon: Icon(Icons.calendar_today_outlined), text: 'Planned'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Error loading orders: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = (snapshot.data?.docs ?? [])
              .map((doc) {
                try {
                  return FoodOrder.fromFirestore(doc);
                } catch (e) {
                  return null;
                }
              })
              .whereType<FoodOrder>()
              .toList();

          orders.sort((a, b) => b.orderTime.compareTo(a.orderTime));

          final activeOrders = orders
              .where(
                (o) =>
                    o.status == OrderStatus.pending ||
                    o.status == OrderStatus.accepted ||
                    o.status == OrderStatus.preparing ||
                    o.status == OrderStatus.ready,
              )
              .toList();

          final completedOrders = orders
              .where(
                (o) =>
                    o.status == OrderStatus.collected ||
                    o.status == OrderStatus.rejected ||
                    o.status == OrderStatus.noShow,
              )
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Active Orders
              _buildActiveOrdersTab(activeOrders),

              // Tab 2: Order History
              _buildCompletedOrdersTab(completedOrders),

              // Tab 3: Planned Orders
              _buildPlannedOrdersTab(),
            ],
          );
        },
      ),
    );
  }

  // ── TAB 1: ACTIVE ORDERS ──────────────────────────────────────────────────

  Widget _buildActiveOrdersTab(List<FoodOrder> activeOrders) {
    if (activeOrders.isEmpty) {
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
                Icons.takeout_dining,
                size: 48,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No active orders right now',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Place an order from Home or Categories!',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: activeOrders.length,
      itemBuilder: (context, index) {
        return _buildOrderCard(context, activeOrders[index], isActive: true);
      },
    );
  }

  // ── TAB 2: COMPLETED ORDERS HISTORY ──────────────────────────────────────

  Widget _buildCompletedOrdersTab(List<FoodOrder> completedOrders) {
    if (completedOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_toggle_off,
              size: 54,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'No past orders yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Your completed food orders will be archived here.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: completedOrders.length,
      itemBuilder: (context, index) {
        return _buildOrderCard(
          context,
          completedOrders[index],
          isActive: false,
        );
      },
    );
  }

  // ── TAB 3: PLANNED UPCOMING ORDERS ─────────────────────────────────────────

  Widget _buildPlannedOrdersTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _plannedOrdersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Planned Meals',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Pre-plan meals for upcoming days & order in 1 tap',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: () => _showAddPlannedOrderDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(Icons.add, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(),

            Expanded(
              child: docs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.calendar_month,
                              size: 56,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No planned meals yet',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create a meal plan for tomorrow or your study breaks to order instantly when ready!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 20),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _showAddPlannedOrderDialog(context),
                              icon: const Icon(Icons.add_task),
                              label: const Text('Create Your First Plan'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                                side: const BorderSide(color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        final title =
                            data['title'] as String? ?? 'Planned Meal';
                        final note = data['note'] as String? ?? '';
                        final total =
                            (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
                        final dateTS = data['plannedDate'] as Timestamp?;
                        final plannedDate = dateTS?.toDate() ?? DateTime.now();
                        final rawItems = data['items'] as List? ?? [];

                        final List<CartItem> parsedItems = rawItems.map((
                          itemMap,
                        ) {
                          return CartItem(
                            id: itemMap['foodItemId'] ?? '',
                            foodItem: FoodItem.fromMap(
                              itemMap as Map<String, dynamic>,
                              id: itemMap['foodItemId'] ?? '',
                            ),
                            quantity:
                                (itemMap['quantity'] as num?)?.toInt() ?? 1,
                            selectedCafe: itemMap['selectedCafe'] as String?,
                          );
                        }).toList();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.event,
                                            size: 14,
                                            color: Colors.orange,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatPlannedDate(plannedDate),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                        color: Colors.red,
                                      ),
                                      onPressed: () =>
                                          _deletePlannedOrder(doc.id),
                                    ),
                                  ],
                                ),
                                if (note.isNotEmpty) ...[
                                  Text(
                                    'Note: $note',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                const Divider(),

                                ...parsedItems.map(
                                  (i) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${i.quantity}x ${i.foodItem.title}',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        Text(
                                          'Tsh ${(i.foodItem.price * i.quantity).toInt()}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Est. Total: Tsh ${total.toInt()}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade900,
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        final cartService = CartService();
                                        for (final item in parsedItems) {
                                          await cartService.addToCart(
                                            item.foodItem,
                                            selectedCafe: item.selectedCafe,
                                          );
                                        }
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Loaded "$title" into cart!',
                                            ),
                                            backgroundColor: Colors.green,
                                            action: SnackBarAction(
                                              label: 'OPEN CART',
                                              textColor: Colors.white,
                                              onPressed: () {
                                                showModalBottomSheet<void>(
                                                  context: context,
                                                  isScrollControlled: true,
                                                  showDragHandle: true,
                                                  builder: (_) =>
                                                      CartBottomSheet(
                                                        onOrderPlaced: () {},
                                                      ),
                                                );
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.shopping_cart_checkout,
                                        size: 16,
                                      ),
                                      label: const Text('Order Now'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade800,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  // ── ORDER CARD WIDGET ──────────────────────────────────────────────────────

  Widget _buildOrderCard(
    BuildContext context,
    FoodOrder order, {
    required bool isActive,
  }) {
    final visuals = _statusVisuals(order.status);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: isActive ? 2 : 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Order ID & Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Order #${order.orderId}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: visuals.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${visuals.icon} ${visuals.label}',
                    style: TextStyle(
                      color: visuals.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Cafe Names
            Builder(
              builder: (context) {
                final cafeNames = order.items
                    .expand((i) => i.displayCafe.split(', '))
                    .map((c) => c.trim())
                    .where((c) => c.isNotEmpty)
                    .toSet()
                    .toList();
                if (cafeNames.isEmpty) return const SizedBox.shrink();
                return Text(
                  cafeNames.length == 1
                      ? 'Cafe: ${cafeNames.first}'
                      : 'Cafes: ${cafeNames.join(", ")}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
            const SizedBox(height: 4),

            // Pickup deadline info if ready
            if (order.status == OrderStatus.ready && order.readyAt != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Ready ${PickupDeadlineService.formatPickupTime(order.readyAt)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  PickupCountdown(
                    pickupDeadline: order.pickupDeadline,
                    deadlineStatus: order.deadlineStatus,
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],

            // Items Summary with Food Pictures
            ...order.items.take(3).map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    // Food Picture Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: item.foodItem.buildImage(
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.foodItem.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Qty: ${item.quantity}'
                            '${item.selectedCafe != null ? " • ${item.selectedCafe}" : ""}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Tsh ${(item.foodItem.price * item.quantity).toInt()}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              );
            }),

            if (order.items.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  '+ ${order.items.length - 3} more item${order.items.length - 3 == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),

            const Divider(),

            // Footer Row: Total, Details button & Reorder button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tsh ${order.totalAmount.toInt()}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[900],
                      ),
                    ),
                    Text(
                      _formatOrderTime(order.orderTime),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Details Button
                    OutlinedButton.icon(
                      onPressed: () => _showOrderDetailsDialog(context, order),
                      icon: const Icon(Icons.info_outline, size: 14),
                      label: const Text(
                        'Details',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Reorder Button for completed/past orders
                    if (!isActive)
                      ElevatedButton.icon(
                        onPressed: () => _handleReorder(order),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text(
                          'Reorder',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── ORDER DETAILS DIALOG ───────────────────────────────────────────────────

  void _showOrderDetailsDialog(BuildContext context, FoodOrder order) {
    final visuals = _statusVisuals(order.status);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Order ID & Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Order #${order.orderId}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: visuals.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
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
                const SizedBox(height: 4),
                Text(
                  'Placed on ${_formatFullDateTime(order.orderTime)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),

                // Status Timeline visualizer
                _buildStatusTimeline(order.status),
                const SizedBox(height: 20),

                const Text(
                  'Ordered Items',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                ...order.items.map((item) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: item.foodItem.buildImage(
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.foodItem.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              if (item.selectedCafe != null)
                                Text(
                                  'Cafe: ${item.selectedCafe}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              Text(
                                'Tsh ${item.foodItem.price.toInt()} x ${item.quantity}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'Tsh ${(item.foodItem.price * item.quantity).toInt()}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 16),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Amount:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Tsh ${order.totalAmount.toInt()}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Actions inside modal: Reorder All or Save to Planned
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showAddPlannedOrderDialog(
                            context,
                            prefilledTitle:
                                'Meal based on Order #${order.orderId.substring(0, 4)}',
                            prefilledItems: order.items,
                          );
                        },
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Save as Plan'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange.shade900,
                          side: BorderSide(color: Colors.orange.shade400),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _handleReorder(order);
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Reorder All'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── STATUS TIMELINE VISUALIZER ─────────────────────────────────────────────

  Widget _buildStatusTimeline(OrderStatus currentStatus) {
    final steps = [
      (status: OrderStatus.pending, label: 'Pending'),
      (status: OrderStatus.accepted, label: 'Accepted'),
      (status: OrderStatus.preparing, label: 'Preparing'),
      (status: OrderStatus.ready, label: 'Ready'),
      (status: OrderStatus.collected, label: 'Collected'),
    ];

    int currentStepIndex = steps.indexWhere((s) => s.status == currentStatus);
    if (currentStatus == OrderStatus.rejected ||
        currentStatus == OrderStatus.noShow) {
      currentStepIndex = -1;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Status Progress',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: steps.asMap().entries.map((entry) {
              final idx = entry.key;
              final step = entry.value;
              final isReached = currentStepIndex >= idx;
              final isCurrent = currentStepIndex == idx;

              return Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: isReached ? Colors.orange : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      step.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isReached ? Colors.orange.shade900 : Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── PLAN MEAL DIALOG ───────────────────────────────────────────────────────

  void _showAddPlannedOrderDialog(
    BuildContext context, {
    String? prefilledTitle,
    List<CartItem>? prefilledItems,
  }) {
    final titleController = TextEditingController(
      text: prefilledTitle ?? 'Tomorrow Lunch',
    );
    final noteController = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));

    final itemsToSave = prefilledItems ?? CartService().cartItems;

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.event_note, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Plan an Upcoming Meal'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Plan ahead for busy study days or upcoming campus events.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Plan Name (e.g. Tomorrow Lunch)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Optional Note (e.g. Pick up at 1 PM)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Target Date: ${_formatPlannedDate(selectedDate)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.calendar_month,
                          color: Colors.orange,
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 30),
                            ),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                      ),
                    ),

                    const Divider(),
                    const Text(
                      'Items in this Meal Plan:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),

                    if (itemsToSave.isEmpty)
                      const Text(
                        'Your cart is currently empty. Add items from Home/Categories or past orders to save a plan.',
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      )
                    else
                      ...itemsToSave.map(
                        (i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${i.quantity}x ${i.foodItem.title}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Text(
                                'Tsh ${(i.foodItem.price * i.quantity).toInt()}',
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: itemsToSave.isEmpty
                      ? null
                      : () {
                          Navigator.pop(context);
                          _saveToPlannedOrders(
                            title: titleController.text.trim().isEmpty
                                ? 'Planned Meal'
                                : titleController.text.trim(),
                            items: itemsToSave,
                            plannedDate: selectedDate,
                            note: noteController.text.trim(),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save Plan'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      // Phase 13: dispose the dialog controllers to prevent memory leaks.
      titleController.dispose();
      noteController.dispose();
    });
  }

  // ── HELPER FORMATTERS ──────────────────────────────────────────────────────

  ({Color color, String icon, String label}) _statusVisuals(
    OrderStatus status,
  ) {
    switch (status) {
      case OrderStatus.pending:
        return (color: Colors.orange, icon: '⏳', label: 'Pending');
      case OrderStatus.accepted:
        return (color: Colors.blue.shade700, icon: '✅', label: 'Accepted');
      case OrderStatus.rejected:
        return (color: Colors.red.shade700, icon: '❌', label: 'Rejected');
      case OrderStatus.preparing:
        return (color: Colors.brown.shade800, icon: '⏱️', label: 'Preparing');
      case OrderStatus.ready:
        return (color: Colors.green.shade800, icon: '⚡', label: 'Ready');
      case OrderStatus.collected:
        return (color: Colors.grey.shade700, icon: '✅', label: 'Collected');
      case OrderStatus.noShow:
        return (color: Colors.red.shade900, icon: '🚫', label: 'No Show');
    }
  }

  String _formatOrderTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatFullDateTime(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hourStr = dt.hour.toString().padLeft(2, '0');
    final minStr = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} at $hourStr:$minStr';
  }

  String _formatPlannedDate(DateTime dt) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    if (dt.year == tomorrow.year &&
        dt.month == tomorrow.month &&
        dt.day == tomorrow.day) {
      return 'Tomorrow';
    }
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }
}
