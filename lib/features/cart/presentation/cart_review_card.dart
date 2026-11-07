import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../application/cart_review_controller.dart';
import '../domain/cart.dart';
import '../domain/reconciliation.dart';

/// Human readable sentence for one reconciliation change. [before] is the
/// cart the user last saw, so removed items still have a name.
String describeCartChange(CartChange change, Cart before) {
  String name(String id) {
    final line = before.lineFor(id);
    return line == null ? 'An item' : '${line.emoji} ${line.name}'.trim();
  }

  return switch (change) {
    PriceChanged(
      :final productId,
      :final oldPricePaise,
      :final newPricePaise
    ) =>
      change.isIncrease
          ? '${name(productId)}: price went up from '
              '${formatMoney(oldPricePaise)} to ${formatMoney(newPricePaise)}.'
          : '${name(productId)}: price dropped from '
              '${formatMoney(oldPricePaise)} to ${formatMoney(newPricePaise)}.',
    OutOfStock(:final productId) =>
      '${name(productId)} is out of stock and was removed.',
    QuantityReduced(
      :final productId,
      :final requestedQuantity,
      :final availableQuantity
    ) =>
      '${name(productId)}: only $availableQuantity available, so your '
          'quantity went from $requestedQuantity to $availableQuantity.',
    ProductUnavailable(:final productId) =>
      '${name(productId)} is no longer sold and was removed.',
    CouponRemoved(:final code, :final reason) => reason == 'EXPIRED'
        ? 'Coupon $code has expired and was removed.'
        : 'Coupon $code is no longer valid and was removed.',
  };
}

/// "Your cart was updated" card listing every change, shown until the user
/// acknowledges it (or taps Place order again).
class CartReviewCard extends ConsumerWidget {
  const CartReviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(cartReviewProvider);
    if (review == null || review.changes.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your cart was updated. Please check before ordering:',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final change in review.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• ${describeCartChange(change, review.before)}'),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    ref.read(cartReviewProvider.notifier).acknowledge(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner shown while the store is closed (remote kill switch).
class StoreClosedBanner extends StatelessWidget {
  const StoreClosedBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: Colors.red.shade900, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
