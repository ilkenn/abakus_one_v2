import 'quantity.dart';

/// The current, materialized on-hand balance of one [InventoryItem] at
/// one [StockLocation] — Phase 7 (`docs/decisions.md` ADR-024). A
/// **read-model only**: never directly settable by any use case except
/// `RecordStockMovement`'s own internal recompute step — the real
/// source of truth is always the `StockMovement` ledger; this exists
/// purely so a screen doesn't have to sum the entire ledger on every
/// read.
class BranchStock {
  const BranchStock({
    required this.inventoryItemId,
    required this.locationId,
    required this.branchId,
    required this.quantityOnHand,
    this.isNegativeStockWarning = false,
    required this.lastMovementId,
    required this.updatedAt,
  });

  final String inventoryItemId;
  final String locationId;
  final String branchId;
  final Quantity quantityOnHand;

  /// Set when a movement was allowed to push [quantityOnHand] negative
  /// under `NegativeStockPolicy.warn` — an honest flag, not acted on
  /// automatically anywhere.
  final bool isNegativeStockWarning;

  final String lastMovementId;
  final DateTime updatedAt;

  BranchStock copyWith({
    required Quantity quantityOnHand,
    bool isNegativeStockWarning = false,
    required String lastMovementId,
    required DateTime updatedAt,
  }) {
    return BranchStock(
      inventoryItemId: inventoryItemId,
      locationId: locationId,
      branchId: branchId,
      quantityOnHand: quantityOnHand,
      isNegativeStockWarning: isNegativeStockWarning,
      lastMovementId: lastMovementId,
      updatedAt: updatedAt,
    );
  }
}
