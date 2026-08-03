import 'quantity.dart';

enum StockReservationStatus { active, released, consumed }

/// Stock set aside for an order before it's actually deducted — Phase 7
/// (`docs/decisions.md` ADR-024). Reserved quantity reduces what a
/// screen should present as "available to sell" without yet being a
/// `StockMovement` — becoming one only when the reservation transitions
/// to [StockReservationStatus.consumed] (a real deduction) or is
/// discarded via [StockReservationStatus.released] (no stock impact at
/// all). See `ConsumeStockForOrder`'s (Phase 7O) doc comment for which
/// order-lifecycle point actually creates/resolves these today.
class StockReservation {
  const StockReservation({
    required this.id,
    required this.branchId,
    required this.inventoryItemId,
    required this.locationId,
    required this.quantityReserved,
    required this.relatedOrderId,
    this.status = StockReservationStatus.active,
    required this.createdAt,
  });

  final String id;
  final String branchId;
  final String inventoryItemId;
  final String locationId;
  final Quantity quantityReserved;
  final String relatedOrderId;
  final StockReservationStatus status;
  final DateTime createdAt;

  StockReservation copyWith({required StockReservationStatus status}) {
    return StockReservation(
      id: id,
      branchId: branchId,
      inventoryItemId: inventoryItemId,
      locationId: locationId,
      quantityReserved: quantityReserved,
      relatedOrderId: relatedOrderId,
      status: status,
      createdAt: createdAt,
    );
  }
}
