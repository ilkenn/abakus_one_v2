import 'quantity.dart';

/// A recorded loss of stock — Phase 7 (`docs/decisions.md` ADR-024).
/// "Waste requires reason" — [reason] is required and non-empty
/// (enforced by `RecordWaste`). Always produces a real
/// `StockMovement` (`StockMovementType.waste`) — waste is never just
/// noted without actually reducing on-hand quantity.
class WasteRecord {
  const WasteRecord({
    required this.id,
    required this.branchId,
    required this.inventoryItemId,
    required this.locationId,
    required this.quantity,
    required this.reason,
    this.relatedStockMovementId,
    required this.reportedByStaffId,
    required this.occurredAt,
  });

  final String id;
  final String branchId;
  final String inventoryItemId;
  final String locationId;
  final Quantity quantity;
  final String reason;
  final String? relatedStockMovementId;
  final String reportedByStaffId;
  final DateTime occurredAt;
}
