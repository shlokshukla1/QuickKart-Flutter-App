import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money.dart';
import '../../app_config/data/config_repository.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/presentation/cart_badge_button.dart';
import '../domain/product.dart';
import 'widgets/paginated_catalog_view.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key, required this.category});

  final Category category;

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  // FIX (listener leak): the subscription was never cancelled, so every
  // visit leaked a listener and a config publish after leaving the screen
  // called setState() on a disposed widget. It is now kept and cancelled.
  StreamSubscription<int>? _configSub;

  @override
  void initState() {
    super.initState();
    // Marketing changes the free-delivery threshold during sales; keep the
    // strip on this screen up to date without a restart.
    // FIX: refresh the app-wide config instead of a private copy, so this
    // strip and the cart's delivery fee always use the same threshold.
    _configSub = ref.read(configRepositoryProvider).remoteUpdates.listen(
        (_) => ref.read(appConfigControllerProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _configSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final freeDeliveryThresholdPaise = ref.watch(
        appConfigControllerProvider.select((c) => c.freeDeliveryThresholdPaise));
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.category.emoji} ${widget.category.name}'),
        actions: const [CartBadgeButton()],
      ),
      body: PaginatedCatalogView(
        categoryId: widget.category.id,
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
