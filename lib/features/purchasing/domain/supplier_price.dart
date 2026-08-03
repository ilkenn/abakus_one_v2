import '../../../shared/models/money.dart';

/// One recorded price for a [SupplierProduct] — Phase 7
/// (`docs/decisions.md` ADR-024). Append-only, exactly like
/// `PurchasePrice` (7M) — "price history," "supplier prices never
/// overwrite historical receipts": a correction is a new
/// [SupplierPrice] row; every [PurchaseOrderLine] snapshots the price
/// it used at creation time rather than referencing this table live,
/// so a later price change never rewrites a past order's recorded
/// cost.
class SupplierPrice {
  const SupplierPrice({
    required this.id,
    required this.supplierProductId,
    required this.pricePerUnit,
    required this.effectiveFrom,
    required this.createdByStaffId,
    required this.createdAt,
  });

  final String id;
  final String supplierProductId;
  final Money pricePerUnit;
  final DateTime effectiveFrom;
  final String createdByStaffId;
  final DateTime createdAt;
}
