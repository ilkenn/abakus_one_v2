import '../domain/purchase_return.dart';

abstract interface class PurchaseReturnRepository {
  Future<void> save(PurchaseReturn purchaseReturn);
  Future<List<PurchaseReturn>> findByBranchId(String branchId);
}

class InMemoryPurchaseReturnRepository implements PurchaseReturnRepository {
  final List<PurchaseReturn> _returns = [];

  @override
  Future<void> save(PurchaseReturn purchaseReturn) async {
    _returns.add(purchaseReturn);
  }

  @override
  Future<List<PurchaseReturn>> findByBranchId(String branchId) async {
    return List.unmodifiable(_returns.where((r) => r.branchId == branchId));
  }
}
