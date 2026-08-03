import 'quantity.dart';
import 'stock_movement_type.dart';

/// One append-only stock ledger entry — the single source of truth for
/// on-hand quantity — Phase 7 (`docs/decisions.md` ADR-024). "Stock
/// cannot be edited by overwriting history. Corrections use append-only
/// movements." No update/delete method exists on
/// `StockMovementRepository` — a correction is always a new
/// [StockMovement] with an opposite-signed [quantityDelta], never an
/// edit to a prior one.
///
/// [idempotencyKey] is required and unique per branch — "every
/// deduction requires an idempotency key," enforced structurally by
/// `RecordStockMovement` rejecting a duplicate
/// (`DuplicateStockMovementViolation`), mirroring
/// `KitchenEventRepository`'s/`CourierEventRepository`'s own
/// idempotency-key discipline.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.branchId,
    required this.inventoryItemId,
    required this.locationId,
    required this.type,
    required this.quantityDelta,
    this.lotId,
    this.relatedOrderId,
    this.relatedPurchaseOrderId,
    this.reason,
    required this.idempotencyKey,
    required this.performedByStaffId,
    required this.occurredAt,
    this.correlationId,
  });

  final String id;
  final String branchId;
  final String inventoryItemId;
  final String locationId;
  final StockMovementType type;

  /// Signed — positive increases on-hand quantity (a receipt, a
  /// transfer in, a positive count correction), negative decreases it
  /// (consumption, waste, a transfer out).
  final Quantity quantityDelta;

  final String? lotId;
  final String? relatedOrderId;
  final String? relatedPurchaseOrderId;
  final String? reason;
  final String idempotencyKey;
  final String performedByStaffId;
  final DateTime occurredAt;

  /// Ties a reversal movement back to the movement it reverses, or a
  /// consumption movement back to the order-lifecycle event that
  /// triggered it — the same "trace one logical action across records"
  /// role `KitchenWorkItem.sourceEventId`/`CourierEvent.correlationId`
  /// already play elsewhere in this codebase.
  final String? correlationId;
}
