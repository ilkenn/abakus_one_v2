import '../../qr/domain/models/restaurant_table.dart';

/// Storage for [RestaurantTable] records — mutable, like
/// [FloorPlanRepository]: a table's current position/status is what
/// matters operationally, not an edit history of it.
abstract interface class RestaurantTableRepository {
  Future<void> save(RestaurantTable table);

  Future<RestaurantTable?> findById(String tableId);

  Future<List<RestaurantTable>> findByFloorPlanId(String floorPlanId);

  Future<List<RestaurantTable>> findByBranchId(String branchId);
}

/// In-memory [RestaurantTableRepository] — the only implementation this
/// sprint.
class InMemoryRestaurantTableRepository implements RestaurantTableRepository {
  final Map<String, RestaurantTable> _tablesById = {};

  @override
  Future<void> save(RestaurantTable table) async {
    _tablesById[table.id] = table;
  }

  @override
  Future<RestaurantTable?> findById(String tableId) async {
    return _tablesById[tableId];
  }

  @override
  Future<List<RestaurantTable>> findByFloorPlanId(String floorPlanId) async {
    return List.unmodifiable(
      _tablesById.values.where((table) => table.floorPlanId == floorPlanId),
    );
  }

  @override
  Future<List<RestaurantTable>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _tablesById.values.where((table) => table.branchId == branchId),
    );
  }
}
