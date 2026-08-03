import '../domain/goods_receipt.dart';

abstract interface class GoodsReceiptRepository {
  Future<void> save(GoodsReceipt receipt);
  Future<List<GoodsReceipt>> findByPurchaseOrderId(String purchaseOrderId);
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
}
