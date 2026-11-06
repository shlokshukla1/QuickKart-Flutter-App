import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../app_config/domain/app_config.dart';
import '../../app_config/domain/home_layout.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/presentation/cart_badge_button.dart';
import '../../cart/presentation/cart_review_card.dart';
import '../../dev_tools/dev_tools_screen.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../search/search_screen.dart';
import '../data/catalog_repository.dart';
import '../domain/product.dart';
import 'catalog_controller.dart';
import 'category_screen.dart';
import 'widgets/paginated_catalog_view.dart';
import 'widgets/product_card.dart';

/// Discounted, in-stock products for the "deals" home section.
final dealsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final page = await ref.watch(catalogRepositoryProvider).getDeals(limit: 10);
  return page.items;
});

/// F2 server-driven home: sections come from the `home_sections` remote
/// config value (HomeLayout.parse) and are rendered in that order. Bad
/// config falls back to the default layout; a section that fails to load
/// hides itself instead of breaking the screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeName = ref.watch(mockServerProvider).storeName;
    final config = ref.watch(appConfigControllerProvider);
    final sections = HomeLayout.parse(config.homeSectionsJson);

    final top = <Widget>[
      if (!config.storeOpen)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: StoreClosedBanner(message: config.storeClosedMessage),
          ),
        ),
      const SliverToBoxAdapter(child: _SearchBar()),
    ];

    final productsIndex = sections.indexOf(HomeSection.allProducts);
    final before =
        productsIndex < 0 ? sections : sections.sublist(0, productsIndex);
    final after = productsIndex < 0
        ? const <HomeSection>[]
        : sections.sublist(productsIndex + 1);

    Future<void> refreshSections() async {
      ref.invalidate(categoriesProvider);
      ref.invalidate(dealsProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(storeName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Text('Delivery in 10 minutes ⚡',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Dev tools',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DevToolsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'My orders',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const OrdersScreen()),
            ),
          ),
          const CartBadgeButton(),
        ],
      ),
      body: productsIndex >= 0
          ? PaginatedCatalogView(
              categoryId: kAllProductsCategory,
              onRefresh: refreshSections,
              headerSlivers: [
                ...top,
                for (final s in before) ..._sectionSlivers(s, config),
                const SliverToBoxAdapter(child: _SectionTitle('All products')),
              ],
              footerSlivers: [
                for (final s in after) ..._sectionSlivers(s, config),
              ],
            )
          // No "all_products": a plain scroll view of the other sections.
          : RefreshIndicator(
              onRefresh: refreshSections,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  ...top,
                  for (final s in sections) ..._sectionSlivers(s, config),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
    );
  }

  List<Widget> _sectionSlivers(HomeSection section, AppConfig config) {
    switch (section) {
      case HomeSection.banner:
        final banner = config.homeBanner;
        // Missing / malformed banner config: just skip the section.
        if (banner == null) return const [];
        return [SliverToBoxAdapter(child: _HomeBannerCard(banner: banner))];
      case HomeSection.categories:
        return const [SliverToBoxAdapter(child: _CategoriesRow())];
      case HomeSection.deals:
        return const [SliverToBoxAdapter(child: _DealsRow())];
      case HomeSection.allProducts:
        return const []; // rendered by PaginatedCatalogView
    }
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
        ),
        child: InputDecorator(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search for products',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Search "milk", "chips"…',
              style: TextStyle(color: Colors.grey)),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}

class _HomeBannerCard extends StatelessWidget {
  const _HomeBannerCard({required this.banner});

  final HomeBanner banner;

  /// `#RRGGBB` / `#AARRGGBB`; anything else falls back to orange so a typo in
  /// the console can't break the screen.
  static Color parseColor(String hex) {
    var h = hex.trim().replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    final value = h.length == 8 ? int.tryParse(h, radix: 16) : null;
    return Color(value ?? 0xFFFF6F00);
  }

  @override
  Widget build(BuildContext context) {
    final color = parseColor(banner.colorHex);
    final onColor =
        color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(banner.title,
              style: TextStyle(
                  color: onColor, fontSize: 20, fontWeight: FontWeight.bold)),
          if (banner.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(banner.subtitle, style: TextStyle(color: onColor)),
          ],
        ],
      ),
    );
  }
}

class _DealsRow extends ConsumerWidget {
  const _DealsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(dealsProvider);
    // Offline / error / no deals: hide the section rather than show an error
    // on the home screen.
    final items = deals.valueOrNull ?? const <Product>[];
    if (deals.isLoading && items.isEmpty) {
      return const SizedBox(
          height: 60, child: Center(child: CircularProgressIndicator()));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Deals for you 🔥'),
        SizedBox(
          height: 260,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) =>
                SizedBox(width: 150, child: ProductCard(product: items[index])),
          ),
        ),
      ],
    );
  }
}

class _CategoriesRow extends ConsumerWidget {
  const _CategoriesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return SizedBox(
      height: 104,
      child: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(categoriesProvider),
            child: const Text("Couldn't load categories. Retry"),
          ),
        ),
        data: (items) => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final c = items[index];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => CategoryScreen(category: c)),
              ),
              child: SizedBox(
                width: 76,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.green.shade50,
                      child:
                          Text(c.emoji, style: const TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(height: 4),
                    Text(c.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
