import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../cart/domain/cart.dart';
import '../../cart/domain/cart_pricing.dart';
import '../domain/order.dart';

final orderApiProvider = Provider<OrderApi>(
  (ref) => OrderApi(ref.watch(apiClientProvider)),
);

class OrderApi {
  OrderApi(this._client);

  final ApiClient _client;

  /// The exact JSON body sent by [placeOrder]. Exposed so the checkout can
  /// tie an idempotency key to this payload.
  static Map<String, dynamic> buildBody(Cart cart, CartPricing pricing) {
    final coupon = cart.coupon;
    return {
      'items': [
        for (final l in cart.lines)
          {
            'productId': l.productId,
            'quantity': l.quantity,
            'unitPricePaise': l.unitPricePaise,
          }
      ],
      // FIX (coupon below minimum): BUSINESS_RULES §3 says a coupon below
      // its minimum gives no discount but the order can still be placed.
      // The server rejects such a code (MIN_ORDER_NOT_MET), so it is only
      // sent once the minimum is reached. The coupon stays in the cart.
      'couponCode': coupon != null && cart.subtotalPaise >= coupon.minOrderPaise
          ? coupon.code
          : null,
      'expectedTotalPaise': pricing.totalPaise,
    };
  }

  /// `POST /v1/orders`. See API_CONTRACT.md for the error codes.
  ///
  /// FIX (double orders): [idempotencyKey] is sent as the `Idempotency-Key`
  /// header, so a retried / repeated request returns the first order instead
  /// of creating a second one.
  Future<Order> placeOrder(
    Cart cart,
    CartPricing pricing, {
    String? idempotencyKey,
  }) async {
    final json = await _client.post(
      '/v1/orders',
      body: buildBody(cart, pricing),
      headers: {
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      },
    ) as Map<String, dynamic>;
    return Order.fromJson(json);
  }

  Future<List<Order>> getOrders() async {
    final json = await _client.get('/v1/orders') as Map<String, dynamic>;
    return (json['items'] as List)
        .map((e) => Order.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Order> getOrder(String id) async {
    final json = await _client.get('/v1/orders/$id') as Map<String, dynamic>;
    return Order.fromJson(json);
  }
}
