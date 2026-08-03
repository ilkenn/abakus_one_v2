import '../domain/branch_stock.dart';

abstract interface class BranchStockRepository {
  Future<void> save(BranchStock stock);
  Future<BranchStock?> findByItemAndLocation(
      String inventoryItemId, String locationId);
  Future<List<BranchStock>> findByBranchId(String branchId);
}

class InMemoryBranchStockRepository implements BranchStockRepository {
  final Map<String, BranchStock> _byKey = {};

  String _key(String inventoryItemId, String locationId) =>
      '$inventoryItemId::$locationId';

  @override
  Future<void> save(BranchStock stock) async =>
      _byKey[_key(stock.inventoryItemId, stock.locationId)] = stock;

  @override
  Future<BranchStock?> findByItemAndLocation(
      String inventoryItemId, String locationId) async {
    return _byKey[_key(inventoryItemId, locationId)];
  }

  @override
  Future<List<BranchStock>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _byKey.values.where((s) => s.branchId == branchId),
    );
  }
}
