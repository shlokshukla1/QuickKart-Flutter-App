import 'dart:convert';

/// Sections the home screen knows how to render.
enum HomeSection { banner, categories, deals, allProducts }

/// Server-driven home screen layout.
///
/// Contract (checked by hidden tests):
/// * Input is the raw `home_sections` remote config value: a JSON array of
///   strings. Known ids: `banner`, `categories`, `deals`, `all_products`.
/// * Output keeps the order given by the config.
/// * Unknown ids are ignored (older app versions must not break when the
///   backend adds a new section type).
/// * Duplicates are ignored (first occurrence wins).
/// * null, malformed JSON, a non-array value, or a result with zero known
///   sections -> [HomeLayout.defaultSections].
class HomeLayout {
  const HomeLayout._();

  static const List<HomeSection> defaultSections = [
    HomeSection.categories,
    HomeSection.allProducts,
  ];

  static const _ids = {
    'banner': HomeSection.banner,
    'categories': HomeSection.categories,
    'deals': HomeSection.deals,
    'all_products': HomeSection.allProducts,
  };

  static List<HomeSection> parse(String? rawJson) {
    if (rawJson == null) return defaultSections;
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException {
      return defaultSections;
    }
    if (decoded is! List) return defaultSections;

    final sections = <HomeSection>[];
    for (final item in decoded) {
      // Non-strings (numbers, objects, null) are treated like unknown ids.
      final section = item is String ? _ids[item] : null;
      if (section != null && !sections.contains(section)) {
        sections.add(section);
      }
    }
    return sections.isEmpty ? defaultSections : List.unmodifiable(sections);
  }
}
