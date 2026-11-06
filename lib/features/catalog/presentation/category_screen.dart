import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/presentation/cart_badge_button.dart';
import '../domain/product.dart';
import 'widgets/paginated_catalog_view.dart';

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key, required this.category});

  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Marketing changes the free-delivery threshold during sales; the strip
    // stays up to date without a restart because AppConfigController
    // follows live config updates itself.
    // FIX (listener leak): this screen used to open its own, never
    // cancelled, config subscription (one leaked listener per visit and
    // setState() after dispose on the next publish) and kept a private copy
    // of the threshold that could disagree with the cart's delivery fee.
    final freeDeliveryThresholdPaise = ref.watch(appConfigControllerProvider
        .select((c) => c.freeDeliveryThresholdPaise));
    return Scaffold(
      appBar: AppBar(
        title: Text('${category.emoji} ${category.name}'),
        actions: const [CartBadgeButton()],
      ),
      body: PaginatedCatalogView(
        categoryId: category.id,
        headerSlivers: [
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              color: Colors.green.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '🛵 Free delivery on orders of '
                '${formatMoney(freeDeliveryThresholdPaise)} or more',
                style: TextStyle(color: Colors.green.shade900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
