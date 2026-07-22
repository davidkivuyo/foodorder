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

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/cart_service.dart';
import '../services/pickup_window_service.dart';

class CartBottomSheet extends StatefulWidget {
  final VoidCallback onOrderPlaced;

  const CartBottomSheet({super.key, required this.onOrderPlaced});

  @override
  State<CartBottomSheet> createState() => _CartBottomSheetState();
}

class _CartBottomSheetState extends State<CartBottomSheet> {
  final CartService _cartService = CartService();
  bool? _isSuspended;

  @override
  void initState() {
    super.initState();
    _loadSuspensionStatus();
    _refreshAvailability();
  }

  Future<void> _refreshAvailability() async {
    await _cartService.refreshCartItemAvailability();
    if (mounted) setState(() {});
  }

  Future<void> _loadSuspensionStatus() async {
    final suspended = await _cartService.isAccountSuspended();
    if (mounted) {
      setState(() => _isSuspended = suspended);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _cartService,
      builder: (context, child) {
        final items = _cartService.cartItems;

        if (items.isEmpty) {
          return SizedBox(
            height: 250,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_pizza,
                      size: 30,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your cart is empty',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Suspension Banner — shown when the account is suspended
              if (_isSuspended == true) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.block,
                          size: 18,
                          color: Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Account Suspended',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'You cannot place orders at this time.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Out-of-Stock Warning Banner — shown when some cart items
              // are no longer available (admin marked them unavailable).
              if (_cartService.hasOutOfStockItems) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: Colors.orange.shade800,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Some items are unavailable',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ..._cartService.outOfStockItems.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(left: 34, top: 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.block,
                                size: 14,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${item.foodItem.title} ×${item.quantity} — removed from stock',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Remove these items to place your order.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'My Cart (${_cartService.totalItemsCount} items)',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _cartService.clearCart();
                    },
                    icon: const Icon(
                      CupertinoIcons.trash,
                      size: 16,
                      color: Colors.red,
                    ),
                    label: const Text(
                      'Clear all',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),

              // Cart Items List
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          // Food Image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: item.foodItem.buildImage(
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Title and Price info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.foodItem.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.storefront_outlined,
                                      size: 14,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        item.displayCafe,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                              Text(
                                'Tsh ${item.foodItem.price.toInt()}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              ],
                            ),
                          ),

                          // Quantity Controls & Delete Button
                          // Quantity Controls & Delete Button
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  _cartService.removeFromCart(item.foodItem);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.remove_rounded,
                                    size: 18,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Text(
                                  '${item.quantity}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  _cartService.addToCart(item.foodItem);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange[100],
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add_rounded,
                                    size: 18,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  _cartService.deleteFromCart(item.foodItem);
                                },
                                icon: const Icon(
                                  CupertinoIcons.delete_simple,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Price Summary
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Subtotal',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  Flexible(
                    child: Text(
                      'Tsh ${_cartService.totalAmount.toInt()}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Queue Fee',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  Text(
                    'Free',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Amount',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      'Tsh ${_cartService.totalAmount.toInt()}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),                          // Place Order Button — disabled when account is suspended
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isSuspended == true ||
                                      _cartService.hasOutOfStockItems
                                  ? null
                                  : () async {
                                      // First check if the account is suspended
                                      final suspended = await _cartService
                                          .isAccountSuspended();
                                      if (!context.mounted) return;

                                      if (suspended) {
                                        setState(() => _isSuspended = true);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: const Row(
                                              children: [
                                                Icon(
                                                  Icons.block,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                                SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    'Your account is suspended. '
                                                    'You cannot place orders at this time.',
                                                  ),
                                                ),
                                              ],
                                            ),
                                            backgroundColor: Colors.red.shade800,
                                            behavior: SnackBarBehavior.floating,
                                            duration: const Duration(seconds: 5),
                                          ),
                                        );
                                        return;
                                      }

                                      // ── Phase 5: Distance-aware pickup window ──
                                      // Location is requested ONLY after the student
                                      // presses "Place Order".
                                      LocationPermission permission;
                                      Position? position;
                                      int pickupWindowMinutes = 20;
                                      double? distanceMeters;
                                      GeoPoint? cafeLocation;
                                      String? cafeId;

                                      try {
                                        permission = await Geolocator
                                            .checkPermission();
                                        if (permission == LocationPermission.denied) {
                                          permission = await Geolocator
                                              .requestPermission();
                                        }

                                        if (permission == LocationPermission.whileInUse ||
                                            permission == LocationPermission.always) {
                                          position = await Geolocator
                                              .getCurrentPosition(
                                            desiredAccuracy:
                                                LocationAccuracy.high,
                                          );

                                          // Look up the selected cafe's GeoPoint
                                          // from the cafes collection.
                                          // Use the first cart item's cafe.
                                          final firstItem =
                                              _cartService.cartItems
                                                  .firstOrNull;
                                          final cafeName =
                                              firstItem?.selectedCafe ??
                                                  firstItem?.foodItem
                                                      .availableCafes
                                                      .firstOrNull;

                                          if (cafeName != null &&
                                              cafeName.isNotEmpty) {
                                            final cafeQuery = await FirebaseFirestore
                                                .instance
                                                .collection('cafes')
                                                .where('name',
                                                    isEqualTo: cafeName)
                                                .limit(1)
                                                .get();

                                            if (cafeQuery.docs
                                                .isNotEmpty) {
                                              final cafeData =
                                                  cafeQuery.docs
                                                      .first
                                                      .data();
                                              cafeLocation =
                                                  cafeData[
                                                          'geoLocation']
                                                      as GeoPoint?;
                                              cafeId =
                                                  cafeQuery.docs
                                                      .first
                                                      .id;
                                            }
                                          }

                                          if (cafeLocation != null) {
                                            distanceMeters = PickupWindowService
                                                .calculateDistance(
                                              startLatitude:
                                                  position.latitude,
                                              startLongitude:
                                                  position.longitude,
                                              endLatitude:
                                                  cafeLocation.latitude,
                                              endLongitude:
                                                  cafeLocation.longitude,
                                            );
                                            pickupWindowMinutes =
                                                PickupWindowService
                                                    .calculatePickupWindow(
                                                        distanceMeters);
                                          }
                                        }
                                      } catch (e) {
                                        // Location unavailable — fall back to default 20 min
                                        debugPrint(
                                          '[CartSheet] Location error: $e',
                                        );
                                      }
                                      // ── End Phase 5 ──

                                      if (!context.mounted) return;

                                      // Capture navigator reference BEFORE the async gap
                                      // so the loading dialog can be dismissed even if
                                      // the widget becomes unmounted.
                                      final navigator = Navigator.of(context);

                                      // Show loading indicator
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (_) => const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );

                                      // Clear sensitive location data from memory
                                      // immediately after use — never persisted.
                                      position = null;

                                      // Place the order with distance data only
                                      final orderId =
                                          await _cartService.placeOrder(
                                        cafeLocation: cafeLocation,
                                        cafeId: cafeId,
                                        distanceMeters: distanceMeters,
                                        pickupWindowMinutes:
                                            pickupWindowMinutes,
                                      );

                                      // Dismiss the loading dialog regardless of outcome.
                                      // Using the captured navigator so this works even
                                      // if the widget became unmounted.
                                      navigator.pop();

                                      if (orderId != null) {
                                        // Dismiss the bottom sheet on success only.
                                        navigator.pop();

                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: const [
                                                Icon(
                                                  Icons.check_circle,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    'Order placed successfully!',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            backgroundColor: Colors.green[800],
                                            duration: const Duration(seconds: 4),
                                          ),
                                        );

                                        // Callback to switch to order tracking screen
                                        widget.onOrderPlaced();
                                      } else {
                                        // Failure: keep the bottom sheet visible so the
                                        // user can retry.  Only dismiss the loading dialog
                                        // (already popped above).
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                              'Failed to place order. Please try again.',
                                            ),
                                            backgroundColor: Colors.red,
                                            duration: const Duration(seconds: 4),
                                          ),
                                        );
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                    backgroundColor: _isSuspended == true
                        ? Colors.grey.shade300
                        : Colors.orange,
                    foregroundColor: _isSuspended == true
                        ? Colors.grey.shade500
                        : Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade500,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isSuspended == true
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.block,
                              size: 18,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Orders Disabled',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'Place Order & Notify Cafe',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
