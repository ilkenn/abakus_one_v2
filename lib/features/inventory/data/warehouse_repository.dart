import '../domain/warehouse.dart';

abstract interface class WarehouseRepository {
  Future<void> save(Warehouse warehouse);
  Future<Warehouse?> findById(String id);
  Future<List<Warehouse>> findByRestaurantId(String restaurantId);
}

class InMemoryWarehouseRepository implements WarehouseRepository {
  final Map<String, Warehouse> _byId = {};

  @override
  Future<void> save(Warehouse warehouse) async =>
      _byId[warehouse.id] = warehouse;

  @override
  Future<Warehouse?> findById(String id) async => _byId[id];

  @override
  Future<List<Warehouse>> findByRestaurantId(String restaurantId) async {
    return List.unmodifiable(
      _byId.values.where((w) => w.restaurantId == restaurantId),
    );
  }
}
