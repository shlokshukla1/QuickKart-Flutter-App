import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/providers.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/application/cart_controller.dart';
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

class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() => const CheckoutState();

  Future<CheckoutResult> placeOrder() async {
    state = const CheckoutState(isPlacingOrder: true);
    final result = await _placeOrder(retryOnTimeout: true);
    state = CheckoutState(lastResult: result);
    return result;
  }

  Future<CheckoutResult> _placeOrder({required bool retryOnTimeout}) async {
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) {
      return const CheckoutFailure('Your cart is empty');
    }
    final pricing =
        CartPricing.compute(cart, ref.read(appConfigControllerProvider));
    final key = await _idempotencyKeyFor(
        jsonEncode(OrderApi.buildBody(cart, pricing)));

    try {
      final order = await ref
          .read(orderApiProvider)
          .placeOrder(cart, pricing, idempotencyKey: key);
      await _forgetIdempotencyKey();
      await ref.read(cartControllerProvider.notifier).clear();
      return CheckoutSuccess(order);
    } on ApiTimeoutException {
      // FIX (double charge): this retry used to send a brand-new request
      // with no Idempotency-Key, so if the first one had reached the server
      // the customer got two orders. Same cart => same key => the server
      // returns the first order instead of creating another.
      if (retryOnTimeout) return _placeOrder(retryOnTimeout: false);
      // FIX (honest message): a timeout does NOT mean the order failed.
      return const CheckoutFailure(
        'We could not confirm your order. It may have been placed, so '
        'please check My orders. Tapping "Place order" again is safe: it '
        'will not create a second order.',
        canRetry: true,
      );
    } on ClientException catch (e) {
      // The server gave a definite "no" for this payload: the next attempt
      // is a new order and gets a new key.
      await _forgetIdempotencyKey();
      return CheckoutFailure(e.message);
    } on ApiException catch (e) {
      // Offline / 5xx: keep the key so the next tap stays idempotent.
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }
  }

  /// Returns the idempotency key for this exact order payload.
  ///
  /// FIX (double charge): the key is stored on the device together with a
  /// fingerprint of the payload. Tapping again (even after an app restart)
  /// with the same cart reuses the key; a changed cart gets a new key, so the
  /// server never answers IDEMPOTENCY_KEY_REUSED.
  Future<String> _idempotencyKeyFor(String fingerprint) async {
    final store = ref.read(keyValueStoreProvider);
    final raw = await store.getString(_kPendingOrderKey);
    if (raw != null) {
      try {
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        if (saved['fingerprint'] == fingerprint) return saved['key'] as String;
      } catch (_) {
        // Corrupt entry: fall through and create a new key.
      }
    }
    final key = const Uuid().v4();
    await store.setString(
      _kPendingOrderKey,
      jsonEncode({'key': key, 'fingerprint': fingerprint}),
    );
    return key;
  }

  Future<void> _forgetIdempotencyKey() =>
      ref.read(keyValueStoreProvider).remove(_kPendingOrderKey);
}
