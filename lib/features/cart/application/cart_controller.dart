import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/domain/product.dart';
import '../data/cart_storage.dart';
import '../domain/cart.dart';
import '../domain/coupon.dart';

/// The cart. Hydrated from storage in `main.dart` before the first frame.
final cartControllerProvider =
    NotifierProvider<CartController, Cart>(CartController.new);

class CartController extends Notifier<Cart> {
  CartStorage get _storage => ref.read(cartStorageProvider);

  // FIX (cart race): writes are queued so they reach storage in the same
  // order the user made the changes; an older cart can never overwrite a
  // newer one.
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Cart build() => const Cart.empty();

  /// Used at startup with the cart restored from storage.
  void hydrate(Cart cart) => state = cart;

  // FIX (QK-101 + cart race): every mutation goes through here.
  // 1. `state` is updated synchronously, so a second fast tap already sees
  //    the first tap's result (before, both taps read the same old cart and
  //    one increment was lost).
  // 2. The new cart is always persisted (before, decrement / remove /
  //    removeCoupon never saved, so removed items came back after restart).
  Future<void> _commit(Cart updated) {
    state = updated;
    return _enqueueWrite(() => _storage.save(updated));
  }

  Future<void> _enqueueWrite(Future<void> Function() write) {
    final next = _pendingWrite.then((_) => write());
    // A failed write must not block the writes queued after it.
    _pendingWrite = next.catchError((Object _) {});
    return next;
  }

  /// Adds one unit of [product].
  Future<void> add(Product product) async {
    final current = state;
    final existing = current.lineFor(product.id);
    final Cart updated;
    if (existing == null) {
      if (!product.inStock) return;
      updated = current.upsertLine(CartLine.fromProduct(product));
    } else {
      if (existing.quantity >= existing.maxPerOrder) return;
      updated = current.updateQuantity(product.id, existing.quantity + 1);
    }
    await _commit(updated);
  }

  /// Adds one more unit of a product that is already in the cart.
  Future<void> increment(String productId) async {
    final current = state;
    final line = current.lineFor(productId);
    if (line == null || line.quantity >= line.maxPerOrder) return;
    await _commit(current.updateQuantity(productId, line.quantity + 1));
  }

  /// Removes one unit (and the line when it reaches zero).
  Future<void> decrement(String productId) async {
    final current = state;
    final line = current.lineFor(productId);
    if (line == null) return;
    // FIX (QK-101): was only changing memory, never saved.
    await _commit(current.updateQuantity(productId, line.quantity - 1));
  }

  Future<void> remove(String productId) async {
    // FIX (QK-101): was only changing memory, never saved.
    await _commit(state.removeLine(productId));
  }

  Future<void> applyCoupon(Coupon coupon) async {
    await _commit(state.withCoupon(coupon));
  }

  Future<void> removeCoupon() async {
    // FIX (QK-101): a removed coupon came back after restart.
    await _commit(state.withoutCoupon());
  }

  /// Replaces the whole cart (e.g. after reconciliation).
  Future<void> replace(Cart cart) async {
    await _commit(cart);
  }

  Future<void> clear() async {
    state = const Cart.empty();
    // Queued too, so a pending save of the old cart can't land after this.
    await _enqueueWrite(_storage.clear);
  }
}
