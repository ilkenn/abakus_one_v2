import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/menu_product.dart';
import '../../domain/services/product_pairing_service.dart';
import 'menu_catalog_provider.dart';

/// "Bununla İyi Gider" suggestions for one product, derived from
/// [ProductPairingService.suggestionsFor] over the real active catalog
/// ([menuProductsProvider]) — never a separate/fabricated data source.
final productPairingProvider =
    Provider.family<List<MenuProduct>, MenuProduct>((ref, product) {
  final catalog = ref.watch(menuProductsProvider);
  return ProductPairingService.suggestionsFor(
    product: product,
    catalog: catalog,
  );
});
