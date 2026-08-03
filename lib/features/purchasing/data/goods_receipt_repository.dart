import '../domain/goods_receipt.dart';

abstract interface class GoodsReceiptRepository {
  Future<void> save(GoodsReceipt receipt);
  Future<List<GoodsReceipt>> findByPurchaseOrderId(String purchaseOrderId);
  Future<GoodsReceipt?> findByIdempotencyKey(String idempotencyKey);
}

class InMemoryGoodsReceiptRepository implements GoodsReceiptRepository {
  final List<GoodsReceipt> _receipts = [];

  @override
  Future<void> save(GoodsReceipt receipt) async {
    _receipts.add(receipt);
  }

  @override
  Future<List<GoodsReceipt>> findByPurchaseOrderId(
      String purchaseOrderId) async {
    return List.unmodifiable(
      _receipts.where((r) => r.purchaseOrderId == purchaseOrderId),
    );
  }

  @override
  Future<GoodsReceipt?> findByIdempotencyKey(String idempotencyKey) async {
    for (final receipt in _receipts) {
      if (receipt.idempotencyKey == idempotencyKey) return receipt;
    }
    return null;
  }
}
