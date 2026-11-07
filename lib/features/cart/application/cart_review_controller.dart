import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../domain/cart.dart';
import '../domain/reconciliation.dart';
import 'cart_controller.dart';
import 'cart_reconciler.dart';

/// Changes found by reconciliation that the user has not acknowledged yet.
class CartReview {
  const CartReview({required this.changes, required this.before});

  final List<CartChange> changes;

  /// The cart as the user last saw it (used for product names in messages,
  /// including items that were removed).
  final Cart before;

  bool get requiresUserReview => changes.any((c) => c.requiresUserReview);
}

/// What the cart screen shows in its "your cart was updated" card.
/// `null` = nothing to review.
final cartReviewProvider = NotifierProvider<CartReviewController, CartReview?>(
    CartReviewController.new);

class CartReviewController extends Notifier<CartReview?> {
  @override
  CartReview? build() => null;

  /// Records the changes of [result] so the user sees them.
  void show(ReconciliationResult result, Cart before) {
    if (!result.hasChanges) return;
    state = CartReview(changes: result.changes, before: before);
  }

  /// The user has seen the changes ("Got it", or a new Place order tap).
  void acknowledge() => state = null;

  /// Brings the cart up to date with the server without placing an order
  /// (called when the cart screen opens, e.g. for a cart built offline).
  ///
  /// Silent when offline: the cart is kept as it is and checkout reconciles
  /// again before ordering.
  Future<void> syncWithServer() async {
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty && cart.coupon == null) return;
    final ReconciliationResult result;
    try {
      result = await ref.read(cartReconcilerProvider).reconcile(cart);
    } on ApiException {
      return;
    }
    if (!result.hasChanges) return;
    // The user edited the cart while we were checking: don't overwrite
    // their edit with a result computed from the old cart.
    if (ref.read(cartControllerProvider) != cart) return;
    await ref.read(cartControllerProvider.notifier).replace(result.cart);
    // Price drops alone are applied silently (BUSINESS_RULES §5); anything
    // else is shown to the user.
    if (result.requiresUserReview) show(result, cart);
  }
}
