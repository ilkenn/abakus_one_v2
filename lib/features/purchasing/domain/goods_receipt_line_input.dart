import '../../inventory/domain/quantity.dart';

/// One caller-requested line for `ReceiveGoods` — before a
/// [GoodsReceiptLine] exists.
class GoodsReceiptLineInput {
  const GoodsReceiptLineInput({
    required this.purchaseOrderLineId,
    required this.receivedQuantity,
  });

  final String purchaseOrderLineId;
  final Quantity receivedQuantity;
}
