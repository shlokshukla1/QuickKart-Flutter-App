import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/home_layout.dart';

void main() {
  const d = HomeLayout.defaultSections;

  test('keeps the configured order', () {
    expect(HomeLayout.parse('["deals","banner","all_products"]'),
        [HomeSection.deals, HomeSection.banner, HomeSection.allProducts]);
    expect(HomeLayout.parse('["banner","categories","deals","all_products"]'), [
      HomeSection.banner,
      HomeSection.categories,
      HomeSection.deals,
      HomeSection.allProducts,
    ]);
  });

  test('ignores unknown ids', () {
    expect(
        HomeLayout.parse(
            '["banner","video_carousel","categories","all_products"]'),
        [HomeSection.banner, HomeSection.categories, HomeSection.allProducts]);
  });

  test('ignores duplicates, first occurrence wins', () {
    expect(HomeLayout.parse('["deals","banner","deals","banner"]'),
        [HomeSection.deals, HomeSection.banner]);
  });

  test('ignores non-string entries', () {
    expect(HomeLayout.parse('["deals", 1, null, {"a":1}, ["x"]]'),
        [HomeSection.deals]);
  });

  test('bad input falls back to the default layout', () {
    expect(HomeLayout.parse(null), d);
    expect(HomeLayout.parse(''), d);
    expect(HomeLayout.parse('[banner,'), d); // malformed preset
    expect(HomeLayout.parse('{"a":1}'), d); // not an array
    expect(HomeLayout.parse('"banner"'), d);
    expect(HomeLayout.parse('[]'), d);
    expect(HomeLayout.parse('["video_carousel"]'), d); // zero known
  });

  test('ids are case sensitive', () {
    expect(HomeLayout.parse('["Banner","ALL_PRODUCTS"]'), d);
  });
}
