import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/providers.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../../cart/application/cart_reconciler.dart';
import '../../cart/application/cart_review_controller.dart';
import '../../cart/domain/cart.dart';
import '../../cart/domain/cart_pricing.dart';
import '../../cart/domain/reconciliation.dart';
import '../data/order_api.dart';
import '../domain/order.dart';

/// Result of [CheckoutController.placeOrder].
sealed class CheckoutResult {
  const CheckoutResult();
}

/// The order was created. The cart has been cleared.
class CheckoutSuccess extends CheckoutResult {
  const CheckoutSuccess(this.order);

  final Order order;
}

/// The cart changed on the server; the user must review it before trying
/// again. The cart in [CartController] has already been updated to
/// `reconciliation.cart`.
class CheckoutNeedsReview extends CheckoutResult {
  const CheckoutNeedsReview(this.reconciliation);

  final ReconciliationResult reconciliation;
}

/// The order was not placed.
class CheckoutFailure extends CheckoutResult {
  const CheckoutFailure(this.message, {this.canRetry = false});

  final String message;
  final bool canRetry;
}

class CheckoutState {
  const CheckoutState({this.isPlacingOrder = false, this.lastResult});

  final bool isPlacingOrder;
  final CheckoutResult? lastResult;
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(
  CheckoutController.new,
);

/// Storage key of the idempotency key for the order currently being placed.
const String _kPendingOrderKey = 'checkout.pending_order.v1';

/// Server errors meaning "your cart no longer matches what we sell".
const _cartConflictCodes = {
  'PRODUCT_UNAVAILABLE',
  'PRICE_CHANGED',
  'QUANTITY_LIMIT',
  'INSUFFICIENT_STOCK',
  'COUPON_INVALID',
  'TOTAL_MISMATCH',
};

/// User-facing messages. Honest about what we know and don't know.
class CheckoutMessages {
  const CheckoutMessages._();

  static const emptyCart = 'Your cart is empty';
  static const offline = "You're offline. Your cart is saved: connect to the "
      'internet and tap Place order again.';
  static const slowBeforeOrder = 'The network is too slow right now. Your '
      'order was not placed. Please try again.';
  static const mayHaveBeenPlaced = 'We could not confirm your order. It may '
      'have been placed, so please check My orders. Tapping "Place order" '
      'again is safe: it will not create a second order.';
  static const serverTrouble = "We're having trouble on our side. Please "
      "try again in a moment; you won't be charged twice.";
  static const cartChangedMeanwhile =
      'Your cart changed while we were checking it. Please try again.';
}

class CheckoutController extends Notifier<CheckoutState> {
  // FIX (double tap): the order currently being placed. A second tap gets
  // the same Future instead of sending a second POST /v1/orders.
  Future<CheckoutResult>? _inFlight;

  @override
  CheckoutState build() => const CheckoutState();

  Future<CheckoutResult> placeOrder() {
    final running = _inFlight;
    if (running != null) return running;
    final future = _run();
    _inFlight = future;
    return future;
  }

  Future<CheckoutResult> _run() async {
    state = const CheckoutState(isPlacingOrder: true);
    try {
      final result = await _placeOrder();
      state = CheckoutState(lastResult: result);
      return result;
    } finally {
      _inFlight = null;
      if (state.isPlacingOrder) state = const CheckoutState();
    }
  }

  CartController get _cart => ref.read(cartControllerProvider.notifier);
  CartReviewController get _review => ref.read(cartReviewProvider.notifier);

  Future<CheckoutResult> _placeOrder() async {
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) return const CheckoutFailure(CheckoutMessages.emptyCart);

    // F2 kill switch: the app already knows the store is closed, so don't
    // even send the request.
    final config = ref.read(appConfigControllerProvider);
    if (!config.storeOpen) return CheckoutFailure(config.storeClosedMessage);

    // Tapping "Place order" again counts as accepting the changes shown.
    _review.acknowledge();

    // A previous attempt for this exact cart timed out: the server may have
    // created that order. Re-send it with the same key BEFORE reconciling
    // (reconciliation would see the stock that order already used and push
    // the user into a review instead of returning their order).
    final pricing = CartPricing.compute(cart, config);
    final pendingKey = await _pendingKeyFor(_fingerprint(cart, pricing));
    if (pendingKey != null) return _send(cart, pricing, pendingKey);

    // F1: make sure the cart matches the server before ordering.
    final ReconciliationResult result;
    try {
      result = await ref.read(cartReconcilerProvider).reconcile(cart);
    } on ApiException catch (e) {
      return _failureBeforeOrder(e);
    }
    if (result.hasChanges) {
      if (ref.read(cartControllerProvider) != cart) {
        return const CheckoutFailure(CheckoutMessages.cartChangedMeanwhile,
            canRetry: true);
      }
      await _cart.replace(result.cart);
      if (result.requiresUserReview) {
        // Price up, stock, discontinued, coupon: the user must see it first.
        _review.show(result, cart);
        return CheckoutNeedsReview(result);
      }
      // Only price drops: applied silently (BUSINESS_RULES §5).
    }

    final fresh = result.cart;
    final freshPricing = CartPricing.compute(fresh, config);
    final key = await _newKeyFor(_fingerprint(fresh, freshPricing));
    return _send(fresh, freshPricing, key);
  }

  Future<CheckoutResult> _send(
    Cart cart,
    CartPricing pricing,
    String key, {
    bool retryOnTimeout = true,
  }) async {
    try {
      final order = await ref
          .read(orderApiProvider)
          .placeOrder(cart, pricing, idempotencyKey: key);
      await _forgetIdempotencyKey();
      await _cart.clear();
      _review.acknowledge();
      return CheckoutSuccess(order);
    } on ApiTimeoutException {
      // FIX (double charge): this retry used to send a brand-new request
      // with no Idempotency-Key, so if the first one had reached the server
      // the customer got two orders. Same key => the server returns the
      // first order instead of creating another.
      if (retryOnTimeout) {
        return _send(cart, pricing, key, retryOnTimeout: false);
      }
      // FIX (honest message): a timeout does NOT mean the order failed.
      return const CheckoutFailure(CheckoutMessages.mayHaveBeenPlaced,
          canRetry: true);
    } on ClientException catch (e) {
      // The server gave a definite "no" for this payload: the next attempt
      // is a new order and gets a new key.
      await _forgetIdempotencyKey();
      if (_cartConflictCodes.contains(e.code)) {
        return _reviewAfterConflict(cart, e);
      }
      return CheckoutFailure(e.message);
    } on ServerException catch (e) {
      if (e.code == 'STORE_CLOSED') {
        // The store closed after our last config fetch: refresh so the UI
        // shows it, and say so.
        await _forgetIdempotencyKey();
        await ref.read(appConfigControllerProvider.notifier).refresh();
        return CheckoutFailure(e.message);
      }
      // Keep the key: a retry stays idempotent.
      return const CheckoutFailure(CheckoutMessages.serverTrouble,
          canRetry: true);
    } on NetworkException {
      return const CheckoutFailure(CheckoutMessages.offline, canRetry: true);
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }
  }

  /// The server rejected the order because something changed after our
  /// reconciliation (e.g. a price changed in between). Reconcile again and
  /// hand the updated cart to the user.
  Future<CheckoutResult> _reviewAfterConflict(
      Cart cart, ClientException error) async {
    if (error.code == 'TOTAL_MISMATCH') {
      // Delivery fee / free-delivery threshold may have changed.
      await ref.read(appConfigControllerProvider.notifier).refresh();
    }
    final ReconciliationResult result;
    try {
      result = await ref.read(cartReconcilerProvider).reconcile(cart);
    } on ApiException catch (e) {
      return _failureBeforeOrder(e);
    }
    if (ref.read(cartControllerProvider) == cart) {
      await _cart.replace(result.cart);
    }
    _review.show(result, cart);
    return CheckoutNeedsReview(result);
  }

  /// Failures that happened before the order request was sent, so we know
  /// for sure that no order was created.
  CheckoutFailure _failureBeforeOrder(ApiException e) => switch (e) {
        NetworkException() =>
          const CheckoutFailure(CheckoutMessages.offline, canRetry: true),
        ApiTimeoutException() => const CheckoutFailure(
            CheckoutMessages.slowBeforeOrder,
            canRetry: true),
        ServerException() =>
          const CheckoutFailure(CheckoutMessages.serverTrouble, canRetry: true),
        ClientException() => CheckoutFailure(e.message),
      };

  String _fingerprint(Cart cart, CartPricing pricing) =>
      jsonEncode(OrderApi.buildBody(cart, pricing));

  /// The key of an earlier, unconfirmed attempt for this exact payload.
  Future<String?> _pendingKeyFor(String fingerprint) async {
    final raw =
        await ref.read(keyValueStoreProvider).getString(_kPendingOrderKey);
    if (raw == null) return null;
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      if (saved['fingerprint'] == fingerprint) return saved['key'] as String;
    } catch (_) {
      // Corrupt entry: treat as no pending attempt.
    }
    return null;
  }

  /// FIX (double charge): a new idempotency key, stored on the device with a
  /// fingerprint of the payload. Tapping again (even after an app restart)
  /// with the same cart reuses it via [_pendingKeyFor]; a changed cart gets a
  /// new key, so the server never answers IDEMPOTENCY_KEY_REUSED.
  Future<String> _newKeyFor(String fingerprint) async {
    final key = const Uuid().v4();
    await ref.read(keyValueStoreProvider).setString(
          _kPendingOrderKey,
          jsonEncode({'key': key, 'fingerprint': fingerprint}),
        );
    return key;
  }

  Future<void> _forgetIdempotencyKey() =>
      ref.read(keyValueStoreProvider).remove(_kPendingOrderKey);
}
