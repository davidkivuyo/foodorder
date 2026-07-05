import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/cart_service.dart';
import 'cart_bottom_sheet.dart';

/// A reusable yellow floating basket button that:
/// - Appears only when the cart is not empty (animated scale).
/// - Shows a red item-count badge.
/// - Opens CartBottomSheet on tap.
///
/// Usage: set `floatingActionButton: const CartFab()` on any Scaffold.
/// Optionally provide [onOrderPlaced] to navigate after an order is placed.
class CartFab extends StatelessWidget {
  /// Called after the user successfully places an order from the cart sheet.
  /// If null, no extra navigation happens.
  final VoidCallback? onOrderPlaced;

  const CartFab({super.key, this.onOrderPlaced});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartService(),
      builder: (context, _) {
        final count = CartService().totalItemsCount;
        return AnimatedScale(
          scale: count > 0 ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          child: FloatingActionButton.extended(
            heroTag: 'cart_fab_${context.hashCode}',
            onPressed: count > 0
                ? () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => CartBottomSheet(
                        onOrderPlaced: onOrderPlaced ?? () {},
                      ),
                    );
                  }
                : null,
            backgroundColor: Colors.orange,
            foregroundColor: Colors.black87,
            elevation: 6,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  CupertinoIcons.bag_fill,
                  size: 24,
                  semanticLabel: 'basket',
                ),
                if (count > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: const Text(
              'View Basket',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        );
      },
    );
  }
}
