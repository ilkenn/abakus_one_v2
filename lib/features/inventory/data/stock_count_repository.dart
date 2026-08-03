import '../domain/stock_count.dart';

abstract interface class StockCountRepository {
  Future<void> save(StockCount count);
  Future<StockCount?> findById(String id);
  Future<List<StockCount>> findByBranchId(String branchId);
}

class InMemoryStockCountRepository implements StockCountRepository {
  final Map<String, StockCount> _byId = {};

  @override
  Future<void> save(StockCount count) async => _byId[count.id] = count;

  @override
  Future<StockCount?> findById(String id) async => _byId[id];

  @override
  Future<List<StockCount>> findByBranchId(String branchId) async {
    return List.unmodifiable(_byId.values.where((c) => c.branchId == branchId));
  }
}
