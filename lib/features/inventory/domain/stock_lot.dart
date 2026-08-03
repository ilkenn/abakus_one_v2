import 'quantity.dart';

/// A single received batch of an [InventoryItem] at one [StockLocation]
/// — Phase 7 (`docs/decisions.md` ADR-024). "Lot/expiry support must be
/// optional but architecturally real" — a `StockMovement` may reference
/// a lot or not; ingredients that don't need lot tracking simply never
/// get one.
class StockLot {
  const StockLot({
    required this.id,
    required this.inventoryItemId,
    required this.locationId,
    this.lotNumber,
    required this.quantityReceived,
    required this.quantityRemaining,
    required this.receivedAt,
    this.expiresAt,
  });

  final String id;
  final String inventoryItemId;
  final String locationId;
  final String? lotNumber;
  final Quantity quantityReceived;

  /// Decremented by each `StockMovement` that consumes from this lot —
  /// never negative (enforced by `RecordStockMovement`).
  final Quantity quantityRemaining;

  final DateTime receivedAt;
  final DateTime? expiresAt;

  StockLot copyWith({required Quantity quantityRemaining}) {
    return StockLot(
      id: id,
      inventoryItemId: inventoryItemId,
      locationId: locationId,
      lotNumber: lotNumber,
      quantityReceived: quantityReceived,
      quantityRemaining: quantityRemaining,
      receivedAt: receivedAt,
      expiresAt: expiresAt,
    );
  }
}
