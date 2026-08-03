import '../domain/inventory_item.dart';

abstract interface class InventoryItemRepository {
  Future<void> save(InventoryItem item);
  Future<InventoryItem?> findById(String id);
  Future<InventoryItem?> findByIngredientId(String ingredientId);
  Future<List<InventoryItem>> findByOrganizationId(String organizationId);
}

class InMemoryInventoryItemRepository implements InventoryItemRepository {
  final Map<String, InventoryItem> _byId = {};

  @override
  Future<void> save(InventoryItem item) async => _byId[item.id] = item;

  @override
  Future<InventoryItem?> findById(String id) async => _byId[id];

  @override
  Future<InventoryItem?> findByIngredientId(String ingredientId) async {
    for (final item in _byId.values) {
      if (item.ingredientId == ingredientId) return item;
    }
    return null;
  }

  @override
  Future<List<InventoryItem>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _byId.values.where((i) => i.organizationId == organizationId),
    );
  }
}
