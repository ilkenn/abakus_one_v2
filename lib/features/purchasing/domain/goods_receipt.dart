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
    required this.idempotencyKey,
  });

  final String id;
  final String purchaseOrderId;
  final String branchId;
  final String locationId;
  final String receivedByStaffId;
  final DateTime receivedAt;
  final DateTime createdAt;

  /// A retried [ReceiveGoods] call with the same key returns the
  /// original receipt instead of recording a second delivery — "do not
  /// double a stock increase," mirroring `RecordStockMovement`'s own
  /// idempotency guarantee.
  final String idempotencyKey;
}
