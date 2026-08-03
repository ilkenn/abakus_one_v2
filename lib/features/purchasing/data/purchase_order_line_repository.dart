import '../domain/purchase_order_line.dart';

abstract interface class PurchaseOrderLineRepository {
  Future<void> save(PurchaseOrderLine line);
  Future<PurchaseOrderLine?> findById(String id);
  Future<List<PurchaseOrderLine>> findByPurchaseOrderId(String purchaseOrderId);
}

class InMemoryPurchaseOrderLineRepository
    implements PurchaseOrderLineRepository {
  final Map<String, PurchaseOrderLine> _byId = {};

  @override
  Future<void> save(PurchaseOrderLine line) async => _byId[line.id] = line;

  @override
  Future<PurchaseOrderLine?> findById(String id) async => _byId[id];

  @override
  Future<List<PurchaseOrderLine>> findByPurchaseOrderId(
      String purchaseOrderId) async {
    return List.unmodifiable(
      _byId.values.where((l) => l.purchaseOrderId == purchaseOrderId),
    );
  }
}
