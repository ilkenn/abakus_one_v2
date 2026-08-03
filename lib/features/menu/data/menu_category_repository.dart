import '../domain/models/menu_category.dart';

/// Persistence for [MenuCategory] — Phase 7 (`docs/decisions.md`
/// ADR-024). `features/menu` had **no repository of any kind** before
/// this — `abakus_menu_catalog.dart` is static mock data with no
/// persistence contract at all (confirmed during the Phase 7 pre-
/// implementation survey). This is additive, not a rewrite of
/// `MenuCategory` itself: the domain model is untouched, and existing
/// screens reading the static catalog are unaffected — `CommitImportDraft`
/// (Phase 7B/7C) is this repository's first real writer.
abstract interface class MenuCategoryRepository {
  Future<void> save(MenuCategory category);
  Future<MenuCategory?> findById(String id);
  Future<List<MenuCategory>> findAll();
}

class InMemoryMenuCategoryRepository implements MenuCategoryRepository {
  InMemoryMenuCategoryRepository({List<MenuCategory> seed = const []})
      : _byId = {for (final category in seed) category.id: category};

  final Map<String, MenuCategory> _byId;

  @override
  Future<void> save(MenuCategory category) async =>
      _byId[category.id] = category;

  @override
  Future<MenuCategory?> findById(String id) async => _byId[id];

  @override
  Future<List<MenuCategory>> findAll() async => List.unmodifiable(_byId.values);
}
