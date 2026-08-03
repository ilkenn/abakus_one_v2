import '../domain/stock_location.dart';

abstract interface class StockLocationRepository {
  Future<void> save(StockLocation location);
  Future<StockLocation?> findById(String id);
  Future<List<StockLocation>> findByBranchId(String branchId);
}

class InMemoryStockLocationRepository implements StockLocationRepository {
  InMemoryStockLocationRepository({List<StockLocation> seed = const []})
      : _byId = {for (final location in seed) location.id: location};

  final Map<String, StockLocation> _byId;

  @override
  Future<void> save(StockLocation location) async =>
      _byId[location.id] = location;

  @override
  Future<StockLocation?> findById(String id) async => _byId[id];

  @override
  Future<List<StockLocation>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _byId.values.where((l) => l.branchId == branchId),
    );
  }
}
