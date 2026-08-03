import '../../../shared/models/money.dart';
import '../../inventory/domain/inventory_unit.dart';
import '../../inventory/domain/quantity.dart';

/// One recorded price paid for a [quantityPurchased] of one
/// ingredient — Phase 7 (`docs/decisions.md` ADR-024). Append-only,
/// like `StockMovement` — a correction is a new [PurchasePrice], never
/// an edit to a past one, so [CostingMethod.weightedAverage]/
/// [CostingMethod.latestPurchase] always resolve consistently against
/// whatever the purchase history actually was at any point in time.
/// Purchasing/supplier linkage (7P) is deliberately not required here
/// — a price can be recorded before that bounded context exists.
class PurchasePrice {
  const PurchasePrice({
    required this.id,
    required this.organizationId,
    required this.ingredientId,
    required this.pricePerUnit,
    required this.unit,
    required this.quantityPurchased,
    this.supplierId,
    required this.recordedAt,
    required this.createdByStaffId,
    required this.createdAt,
  });

  final String id;
  final String organizationId;
  final String ingredientId;

  /// Price for exactly one whole [unit] (e.g. ₺45.00 per kg) — not
  /// scaled by [quantityPurchased].
  final Money pricePerUnit;
  final InventoryUnit unit;

  /// How much was actually purchased at [pricePerUnit] — the weight
  /// used by [CostingMethod.weightedAverage].
  final Quantity quantityPurchased;

  final String? supplierId;
  final DateTime recordedAt;
  final String createdByStaffId;
  final DateTime createdAt;
}
