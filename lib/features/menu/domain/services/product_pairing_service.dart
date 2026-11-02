import '../models/menu_product.dart';

/// "Bununla İyi Gider" (Smart Pairing) — a lightweight, fully client-side
/// suggestion heuristic. No backend/recommendation service exists or is
/// added for this; the entire rule is the explicit, documented
/// complementary-category map below, evaluated over whatever products are
/// already in the active catalog.
///
/// Deliberately kept in the domain layer (not inline in a widget's
/// `build()`, per CLAUDE.md §4) so it's a plain, synchronous, unit-testable
/// function of its inputs.
abstract final class ProductPairingService {
  ProductPairingService._();

  /// The heuristic itself: which category a product is in determines which
  /// *other* category/categories are offered as a pairing — e.g. a Bowl
  /// suggests a drink or a snack, a main course (Tava) suggests a salad.
  /// Chosen from the real, currently-active category set
  /// (`AbakusMenuCatalog`'s 2026-10-28 PDF refresh ids) — a category id not
  /// present here (e.g. a pre-refresh/inactive id, or a test-only id)
  /// simply yields no suggestions rather than guessing.
  static const Map<String, List<String>> _complementaryCategoryIds = {
    'cat_kahvalti': ['cat_tartine', 'cat_icecekler'],
    'cat_tartine': ['cat_kahvalti', 'cat_icecekler'],
    'cat_bowl2': ['cat_icecekler', 'cat_atistirmalik2'],
    'cat_tava': ['cat_salata2', 'cat_icecekler'],
    'cat_salata2': ['cat_tava', 'cat_icecekler'],
    'cat_hamburger2': ['cat_atistirmalik2', 'cat_icecekler'],
    'cat_wrap2': ['cat_salata2', 'cat_icecekler'],
    'cat_makarna2': ['cat_salata2', 'cat_icecekler'],
    'cat_atistirmalik2': ['cat_hamburger2', 'cat_icecekler'],
    'cat_icecekler': ['cat_atistirmalik2', 'cat_kahvalti'],
  };

  /// At most this many suggestions — decision-fatigue guardrail (UX
  /// Guidelines), not a technical limit.
  static const int maxSuggestions = 4;

  /// Suggestions for [product], drawn from [catalog] (the full active
  /// product list). Returns an empty list — never throws, never falls back
  /// to an arbitrary/random product — when [product]'s category has no
  /// entry in [_complementaryCategoryIds] (e.g. a test fixture's synthetic
  /// category id) or when nothing in [catalog] matches.
  ///
  /// Excludes: [product] itself, unavailable products, and anything already
  /// in the same category as [product] (a pairing suggestion is explicitly
  /// cross-category — "goes well with", not "more of the same"). Ordering
  /// is deterministic: featured products first, then by name, so the same
  /// inputs always produce the same output (required for the unit test and
  /// for a stable UI that doesn't reshuffle on rebuild).
  static List<MenuProduct> suggestionsFor({
    required MenuProduct product,
    required List<MenuProduct> catalog,
  }) {
    final complementaryIds = _complementaryCategoryIds[product.categoryId];
    if (complementaryIds == null || complementaryIds.isEmpty) return const [];

    final candidates = catalog.where((candidate) {
      return candidate.id != product.id &&
          candidate.isAvailable &&
          candidate.categoryId != product.categoryId &&
          complementaryIds.contains(candidate.categoryId);
    }).toList()
      ..sort((a, b) {
        if (a.isFeatured != b.isFeatured) {
          return a.isFeatured ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });

    return candidates.take(maxSuggestions).toList();
  }
}
