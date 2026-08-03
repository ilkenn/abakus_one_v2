import '../domain/models/menu_product.dart';

/// Persistence for [MenuProduct] — Phase 7 (`docs/decisions.md`
/// ADR-024). See `MenuCategoryRepository`'s doc comment for why this is
/// additive, not a rewrite — `features/menu` had no repository at all
/// before Phase 7.
abstract interface class MenuProductRepository {
  Future<void> save(MenuProduct product);
  Future<MenuProduct?> findById(String id);
  Future<List<MenuProduct>> findByCategoryId(String categoryId);
  Future<List<MenuProduct>> findAll();
}

class InMemoryMenuProductRepository implements MenuProductRepository {
  InMemoryMenuProductRepository({List<MenuProduct> seed = const []})
      : _byId = {for (final product in seed) product.id: product};

  final Map<String, MenuProduct> _byId;

  @override
  Future<void> save(MenuProduct product) async => _byId[product.id] = product;

  @override
  Future<MenuProduct?> findById(String id) async => _byId[id];

  @override
  Future<List<MenuProduct>> findByCategoryId(String categoryId) async {
    return List.unmodifiable(
      _byId.values.where((p) => p.categoryId == categoryId),
    );
  }

  @override
  Future<List<MenuProduct>> findAll() async => List.unmodifiable(_byId.values);
}
