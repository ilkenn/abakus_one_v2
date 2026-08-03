import '../domain/goods_receipt_line.dart';

abstract interface class GoodsReceiptLineRepository {
  Future<void> save(GoodsReceiptLine line);
  Future<GoodsReceiptLine?> findById(String id);
  Future<List<GoodsReceiptLine>> findByGoodsReceiptId(String goodsReceiptId);
  Future<List<GoodsReceiptLine>> findByPurchaseOrderLineId(
      String purchaseOrderLineId);
}

class InMemoryGoodsReceiptLineRepository implements GoodsReceiptLineRepository {
  final Map<String, GoodsReceiptLine> _byId = {};

  @override
  Future<void> save(GoodsReceiptLine line) async => _byId[line.id] = line;

  @override
  Future<GoodsReceiptLine?> findById(String id) async => _byId[id];

  @override
  Future<List<GoodsReceiptLine>> findByGoodsReceiptId(
      String goodsReceiptId) async {
    return List.unmodifiable(
      _byId.values.where((l) => l.goodsReceiptId == goodsReceiptId),
    );
  }

  @override
  Future<List<GoodsReceiptLine>> findByPurchaseOrderLineId(
      String purchaseOrderLineId) async {
    return List.unmodifiable(
      _byId.values.where((l) => l.purchaseOrderLineId == purchaseOrderLineId),
    );
  }
}
