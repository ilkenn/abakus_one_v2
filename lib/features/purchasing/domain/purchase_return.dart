import '../../inventory/domain/quantity.dart';

/// Goods sent back to a [Supplier] after receipt — Phase 7
/// (`docs/decisions.md` ADR-024). References the specific
/// [GoodsReceiptLine] being returned from — never a bare quantity
/// disconnected from what was actually received. [reason] is
/// required, matching every other reason-requiring correction in
/// Phase 7 (waste, manual stock adjustments, manual nutrition/
/// allergen overrides).
class PurchaseReturn {
  const PurchaseReturn({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.supplierId,
    required this.goodsReceiptLineId,
    required this.returnedQuantity,
    required this.reason,
    required this.createdByStaffId,
    required this.createdAt,
  });

  final String id;
  final String organizationId;
  final String branchId;
  final String supplierId;
  final String goodsReceiptLineId;
  final Quantity returnedQuantity;
  final String reason;
  final String createdByStaffId;
  final DateTime createdAt;
}
