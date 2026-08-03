import 'quantity.dart';

enum StockAdjustmentStatus { pending, approved, rejected }

/// A manual stock correction request — Phase 7 (`docs/decisions.md`
/// ADR-024). [reason] is required at construction (never an empty
/// string, enforced by `RecordStockAdjustment`) — "waste requires
/// reason" extended to every manual adjustment, not just waste.
/// Approving one produces a real `StockMovement`
/// (`StockMovementType.adjustment`); a rejected one never does.
class StockAdjustment {
  const StockAdjustment({
    required this.id,
    required this.branchId,
    required this.inventoryItemId,
    required this.locationId,
    required this.quantityDelta,
    required this.reason,
    required this.requestedByStaffId,
    this.status = StockAdjustmentStatus.pending,
    this.approvedByStaffId,
    this.approvedAt,
    required this.createdAt,
  });

  final String id;
  final String branchId;
  final String inventoryItemId;
  final String locationId;
  final Quantity quantityDelta;
  final String reason;
  final String requestedByStaffId;
  final StockAdjustmentStatus status;
  final String? approvedByStaffId;
  final DateTime? approvedAt;
  final DateTime createdAt;

  StockAdjustment copyWith({
    required StockAdjustmentStatus status,
    String? approvedByStaffId,
    DateTime? approvedAt,
  }) {
    return StockAdjustment(
      id: id,
      branchId: branchId,
      inventoryItemId: inventoryItemId,
      locationId: locationId,
      quantityDelta: quantityDelta,
      reason: reason,
      requestedByStaffId: requestedByStaffId,
      status: status,
      approvedByStaffId: approvedByStaffId ?? this.approvedByStaffId,
      approvedAt: approvedAt ?? this.approvedAt,
      createdAt: createdAt,
    );
  }
}
