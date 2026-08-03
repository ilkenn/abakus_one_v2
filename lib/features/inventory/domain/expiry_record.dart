import 'quantity.dart';

/// A [StockLot] reaching or being disposed at expiry — Phase 7
/// (`docs/decisions.md` ADR-024). "Expired inventory cannot be treated
/// as saleable stock" — disposing an expired lot always produces a real
/// `StockMovement` (`StockMovementType.waste`) reducing on-hand
/// quantity, exactly like `WasteRecord`; this record exists
/// specifically to distinguish *why* stock was lost (expiry vs.
/// operational waste) for separate reporting — "waste and count
/// variance must remain separately reportable" extended to expiry too.
class ExpiryRecord {
  const ExpiryRecord({
    required this.id,
    required this.lotId,
    required this.inventoryItemId,
    required this.locationId,
    required this.disposedQuantity,
    this.relatedStockMovementId,
    required this.disposedByStaffId,
    required this.disposedAt,
  });

  final String id;
  final String lotId;
  final String inventoryItemId;
  final String locationId;
  final Quantity disposedQuantity;
  final String? relatedStockMovementId;
  final String disposedByStaffId;
  final DateTime disposedAt;
}
