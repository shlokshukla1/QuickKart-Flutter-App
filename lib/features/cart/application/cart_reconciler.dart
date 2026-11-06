import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../catalog/data/catalog_api.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/product.dart';
import '../data/coupon_api.dart';
import '../domain/cart.dart';
import '../domain/coupon.dart';
import '../domain/reconciliation.dart';

final cartReconcilerProvider = Provider<CartReconciler>(
  (ref) => CartReconciler(
    catalogApi: ref.watch(catalogApiProvider),
    couponApi: ref.watch(couponApiProvider),
  ),
);

/// Compares a local cart with the server's current state.
class CartReconciler {
  CartReconciler({required this.catalogApi, required this.couponApi});

  final CatalogApi catalogApi;
  final CouponApi couponApi;

  /// The batch endpoint accepts at most 50 ids per request.
  static const _maxIdsPerRequest = 50;

  /// Contract (checked by hidden tests - see ASSIGNMENT.md, Feature 1):
  ///
  /// Returns a [ReconciliationResult] whose `cart` is what could be ordered
  /// right now:
  /// * every line's `unitPricePaise` equals the server's current price;
  /// * every line's `quantity` is `<= min(stock, maxPerOrder)` and its
  ///   `maxPerOrder` is refreshed to that same value;
  /// * lines whose product is out of stock or no longer sold are removed;
  /// * the coupon is removed if it is expired or unknown, otherwise it is
  ///   refreshed with the server's latest rules (a coupon whose minimum
  ///   order is not met stays in the cart - see BUSINESS_RULES.md);
  /// * the order of the remaining lines is preserved.
  ///
  /// `changes` lists every difference (one [CartChange] per product/coupon
  /// issue). An unchanged cart returns an empty list and an equal cart.
  ///
  /// Throws an `ApiException` if the server cannot be reached. It must never
  /// return a partially reconciled cart.
  Future<ReconciliationResult> reconcile(Cart cart) async {
    // 1. Fetch EVERYTHING first. Any failure throws before a single line is
    //    touched, so a partially reconciled cart can never be returned.
    final serverProducts = <String, Product>{};
    final missing = <String>{};
    final ids = [for (final l in cart.lines) l.productId];
    for (var i = 0; i < ids.length; i += _maxIdsPerRequest) {
      final chunk = ids.sublist(i, (i + _maxIdsPerRequest).clamp(0, ids.length));
      final batch = await catalogApi.getProductsByIds(chunk);
      for (final p in batch.products) {
        serverProducts[p.id] = p;
      }
      missing.addAll(batch.missingIds);
    }
    final couponCheck = await _checkCoupon(cart.coupon);

    // 2. Build the orderable cart, keeping the original line order.
    final changes = <CartChange>[];
    final lines = <CartLine>[];
    for (final line in cart.lines) {
      final product = serverProducts[line.productId];
      if (product == null || missing.contains(line.productId)) {
        // No longer sold (or unknown to the server): never ordered.
        changes.add(ProductUnavailable(productId: line.productId));
        continue;
      }
      if (!product.inStock) {
        changes.add(OutOfStock(productId: line.productId));
        continue;
      }

      final available = product.purchasableQuantity; // min(stock, limit)
      var quantity = line.quantity;
      if (quantity > available) {
        changes.add(QuantityReduced(
          productId: line.productId,
          requestedQuantity: quantity,
          availableQuantity: available,
        ));
        quantity = available;
      }
      if (product.pricePaise != line.unitPricePaise) {
        changes.add(PriceChanged(
          productId: line.productId,
          oldPricePaise: line.unitPricePaise,
          newPricePaise: product.pricePaise,
        ));
      }
      lines.add(line.copyWith(
        unitPricePaise: product.pricePaise,
        quantity: quantity,
        maxPerOrder: available,
      ));
    }

    final Coupon? coupon;
    switch (couponCheck) {
      case _CouponValid(:final latest):
        coupon = latest; // refreshed with the server's latest rules
      case _CouponGone(:final code, :final reason):
        coupon = null;
        changes.add(CouponRemoved(code: code, reason: reason));
      case null:
        coupon = null;
    }

    return ReconciliationResult(
      cart: Cart(lines: lines, coupon: coupon),
      changes: changes,
    );
  }

  /// Re-validates the coupon. `null` when the cart has no coupon.
  /// Network errors are rethrown (the whole reconciliation fails).
  Future<_CouponCheck?> _checkCoupon(Coupon? coupon) async {
    if (coupon == null) return null;
    try {
      return _CouponValid(await couponApi.validate(coupon.code));
    } on ClientException catch (e) {
      switch (e.code) {
        case 'COUPON_EXPIRED':
          return _CouponGone(coupon.code, 'EXPIRED');
        case 'COUPON_NOT_FOUND':
          return _CouponGone(coupon.code, 'NOT_FOUND');
        default:
          rethrow;
      }
    }
  }
}

sealed class _CouponCheck {
  const _CouponCheck();
}

class _CouponValid extends _CouponCheck {
  const _CouponValid(this.latest);

  /// The coupon with the server's latest rules.
  final Coupon latest;
}

class _CouponGone extends _CouponCheck {
  const _CouponGone(this.code, this.reason);

  final String code;
  final String reason;
}
