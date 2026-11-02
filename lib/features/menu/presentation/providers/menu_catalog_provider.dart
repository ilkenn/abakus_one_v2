import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/abakus_menu_catalog.dart';
import '../../domain/models/menu_category.dart';
import '../../domain/models/menu_product.dart';

/// The live menu's categories, in catalog order — [MenuCategory.isActive]
/// filtered out here, not left to every consumer to remember. 2026-10-28
/// PDF menu refresh: the pre-refresh categories/products are kept in
/// [AbakusMenuCatalog] with `isActive: false` rather than deleted (see
/// that class's own doc comment on why), so this is the one place that
/// decides what a customer actually sees.
final menuCategoriesProvider = Provider<List<MenuCategory>>((ref) {
  return AbakusMenuCatalog.categories.where((c) => c.isActive).toList();
});

/// Every real product belonging to an active category — see
/// [menuCategoriesProvider]'s own doc comment. A product itself has no
/// `isActive` flag; it's gated entirely by its category's.
final menuProductsProvider = Provider<List<MenuProduct>>((ref) {
  final activeCategoryIds = AbakusMenuCatalog.categories
      .where((c) => c.isActive)
      .map((c) => c.id)
      .toSet();
  return AbakusMenuCatalog.products
      .where((p) => activeCategoryIds.contains(p.categoryId))
      .toList();
});

/// The real site's "Çok Satanlar" (best sellers) cross-listing — scoped to
/// [menuProductsProvider]'s already-active set, not the raw catalog, so a
/// pre-refresh featured product hidden by [menuCategoriesProvider]'s
/// `isActive` filter never reappears here.
final featuredMenuProductsProvider = Provider<List<MenuProduct>>((ref) {
  return ref.watch(menuProductsProvider).where((p) => p.isFeatured).toList();
});

/// 2026-10-30 product-configurator — "Yanına En Çok Yakışanlar" drink
/// cross-sell, scoped to the real `cat_icecekler` products. Only 4 real
/// drinks exist in the catalog today (3 Ayran flavors + "CocaCola Şişe") —
/// the spec's "Soğuk Çay"/"Su" are not real catalog items, so they are
/// deliberately not synthesized here; this provider only ever surfaces
/// real, orderable products.
final drinkCrossSellProductsProvider = Provider<List<MenuProduct>>((ref) {
  return ref
      .watch(menuProductsProvider)
      .where((p) => p.categoryId == AbakusMenuCatalog.drinkCategory.id)
      .toList();
});
