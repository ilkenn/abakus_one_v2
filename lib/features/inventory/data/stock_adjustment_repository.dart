import '../domain/stock_adjustment.dart';

abstract interface class StockAdjustmentRepository {
  Future<void> save(StockAdjustment adjustment);
  Future<StockAdjustment?> findById(String id);
  Future<List<StockAdjustment>> findByBranchId(String branchId);
}

class InMemoryStockAdjustmentRepository implements StockAdjustmentRepository {
  final Map<String, StockAdjustment> _byId = {};

  @override
  Future<void> save(StockAdjustment adjustment) async =>
      _byId[adjustment.id] = adjustment;

  @override
  Future<StockAdjustment?> findById(String id) async => _byId[id];

  @override
  Future<List<StockAdjustment>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _byId.values.where((a) => a.branchId == branchId),
    );
  }
}
