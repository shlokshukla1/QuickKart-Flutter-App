import '../../../core/utils/money.dart';
import '../domain/product.dart';

/// Maps the API representation of a product (see API_CONTRACT.md) to the
/// domain [Product].
class ProductDto {
  const ProductDto._();

  static Product fromJson(Map<String, dynamic> json) {
    final pricePaise = rupeesToPaise(json['price'] as num);
    // FIX (legacy products crash): products from the older catalog service
    // (e.g. Toned Milk, Cheese Slices, Soan Papdi) send `"mrp": null` and
    // `"stock": "120"` (a String). The strict `as num` / `as int` casts threw
    // a TypeError, so the Dairy list spun forever and "milk" search broke.
    // Missing MRP = no discount (MRP = price); numeric strings are parsed.
    final mrp = _num(json['mrp']);
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String,
      emoji: json['emoji'] as String? ?? '🛒',
      unit: json['unit'] as String? ?? '',
      pricePaise: pricePaise,
      mrpPaise: mrp == null ? pricePaise : rupeesToPaise(mrp),
      stock: _int(json['stock']) ?? 0,
      maxPerOrder: _int(json['maxPerOrder']) ?? 10,
    );
  }

  static List<Product> listFromJson(Object? json) => (json as List)
      .map((e) => fromJson(e as Map<String, dynamic>))
      .toList();

  static num? _num(Object? v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v.trim());
    return null;
  }

  static int? _int(Object? v) => _num(v)?.toInt();
}
