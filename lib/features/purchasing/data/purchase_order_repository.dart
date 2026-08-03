import '../domain/purchase_order.dart';

abstract interface class PurchaseOrderRepository {
  Future<void> save(PurchaseOrder order);
  Future<PurchaseOrder?> findById(String id);
  Future<List<PurchaseOrder>> findByBranchId(String branchId);
}

class InMemoryPurchaseOrderRepository implements PurchaseOrderRepository {
  final Map<String, PurchaseOrder> _byId = {};

  @override
  Future<void> save(PurchaseOrder order) async => _byId[order.id] = order;

  @override
  Future<PurchaseOrder?> findById(String id) async => _byId[id];

  @override
  Future<List<PurchaseOrder>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _byId.values.where((o) => o.branchId == branchId),
    );
  }
}
