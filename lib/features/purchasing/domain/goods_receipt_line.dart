import '../../inventory/domain/quantity.dart';

/// One received line of a [GoodsReceipt] — Phase 7
/// (`docs/decisions.md` ADR-024). [receivedQuantity] is recorded
/// exactly as counted, even when it differs from the originating
/// [PurchaseOrderLine.orderedQuantity] — "partial receipt, over/under
/// receipt" is an honest fact to record, never silently corrected to
/// match what was ordered.
class GoodsReceiptLine {
  const GoodsReceiptLine({
    required this.id,
    required this.goodsReceiptId,
    required this.purchaseOrderLineId,
    required this.supplierProductId,
    required this.receivedQuantity,
  });

  final String id;
  final String goodsReceiptId;
  final String purchaseOrderLineId;
  final String supplierProductId;
  final Quantity receivedQuantity;
}
