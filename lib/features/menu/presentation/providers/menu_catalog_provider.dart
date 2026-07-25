import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/abakus_menu_catalog.dart';
import '../../domain/models/menu_category.dart';
import '../../domain/models/menu_product.dart';

/// The real menu's categories, in the real site's order.
final menuCategoriesProvider = Provider<List<MenuCategory>>((ref) {
  return AbakusMenuCatalog.categories;
});

/// Every real product, unfiltered.
final menuProductsProvider = Provider<List<MenuProduct>>((ref) {
  return AbakusMenuCatalog.products;
});

/// The real site's "Çok Satanlar" (best sellers) cross-listing.
final featuredMenuProductsProvider = Provider<List<MenuProduct>>((ref) {
  return AbakusMenuCatalog.products.where((p) => p.isFeatured).toList();
});
