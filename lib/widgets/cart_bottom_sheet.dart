import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/cart_service.dart';

class CartBottomSheet extends StatelessWidget {
  final VoidCallback onOrderPlaced;

  const CartBottomSheet({super.key, required this.onOrderPlaced});

  @override
  Widget build(BuildContext context) {
    final cartService = CartService();

    return ListenableBuilder(
      listenable: cartService,
      builder: (context, child) {
        final items = cartService.cartItems;

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
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Cart (${cartService.totalItemsCount} items)',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      cartService.clearCart();
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
                            child: Image.asset(
                              item.foodItem.image,
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
                                Text(
                                  'Cafe ${item.foodItem.cafe}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tsh ${item.foodItem.price.toInt()}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Quantity Controls & Delete Button
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  cartService.removeFromCart(item.foodItem);
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
                                  cartService.addToCart(item.foodItem);
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
                                  cartService.deleteFromCart(item.foodItem);
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
                  Text(
                    'Tsh ${cartService.totalAmount.toInt()}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Tsh ${cartService.totalAmount.toInt()}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Place Order Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    // Place the order
                    cartService.placeOrder();

                    // Close Bottom Sheet
                    Navigator.pop(context);

                    // Show dynamic feedback
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: const [
                            Icon(Icons.check_circle, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Order placed successfully! Sent to Cafe Admin.',
                            ),
                          ],
                        ),
                        backgroundColor: Colors.green[800],
                        duration: const Duration(seconds: 4),
                      ),
                    );

                    // Callback to switch to order tracking screen
                    onOrderPlaced();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Place Order & Notify Cafe',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
