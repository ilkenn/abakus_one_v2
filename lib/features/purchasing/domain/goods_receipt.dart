/// One delivery event against a [PurchaseOrder] — Phase 7
/// (`docs/decisions.md` ADR-024). A single [PurchaseOrder] may have
/// multiple [GoodsReceipt]s (partial deliveries) — never mutated after
/// creation; each new delivery is a new receipt.
class GoodsReceipt {
  const GoodsReceipt({
    required this.id,
    required this.purchaseOrderId,
    required this.branchId,
    required this.locationId,
    required this.receivedByStaffId,
    required this.receivedAt,
    required this.createdAt,
  });

  final String id;
  final String purchaseOrderId;
  final String branchId;
  final String locationId;
  final String receivedByStaffId;
  final DateTime receivedAt;
  final DateTime createdAt;
}
