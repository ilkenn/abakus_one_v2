import '../../../../core/errors/business_rule_violation.dart';
import '../../data/branch_stock_repository.dart';
import '../../data/inventory_audit_entry_repository.dart';
import '../../data/inventory_item_repository.dart';
import '../../data/stock_lot_repository.dart';
import '../../data/stock_movement_repository.dart';
import '../../domain/branch_stock.dart';
import '../../domain/inventory_audit_entry.dart';
import '../../domain/inventory_audit_event_type.dart';
import '../../domain/negative_stock_policy.dart';
import '../../domain/quantity.dart';
import '../../domain/stock_movement.dart';
import '../../domain/stock_movement_type.dart';
import '../identity/stock_movement_id_generator.dart';

/// The single write path for every stock change in this codebase —
/// Phase 7 (`docs/decisions.md` ADR-024). "Stock cannot be edited by
/// overwriting history. Corrections use append-only movements" — this
/// use case only ever **appends** a new `StockMovement`, then
/// recomputes the `BranchStock` materialized balance from it; nothing
/// else in this codebase is allowed to write `BranchStock` directly.
///
/// **A trusted internal primitive, not a screen-facing entry point**:
/// deliberately has no `PosAuthorizationPolicy` dependency of its own —
/// mirrors `CompleteKitchenOrderPreparation` calling `RecordKitchenEvent`
/// internally after its *own* authorization check already passed.
/// Every caller (`RecordManualStockMovement`, `ApproveStockAdjustment`,
/// `RecordWaste`, the Phase 7O order-completion hook) is responsible
/// for checking the permission appropriate to *itself*
/// (`recordStockMovement` for a manual entry, `recordWaste` for waste,
/// an automatic system trigger for order-driven consumption) before
/// calling this. Never expose this type directly to a screen.
///
/// **Idempotent by [idempotencyKey]**: a duplicate call with the same
/// key returns the original movement's already-applied `BranchStock`
/// state without appending a second time — "do not deduct stock
/// twice," "every deduction requires an idempotency key."
///
/// **Negative-stock policy**: consults `InventoryItem
/// .negativeStockPolicy` — `forbid` throws
/// [NegativeStockNotAllowedViolation] rather than applying the
/// movement; `warn` applies it but flags the resulting `BranchStock`;
/// `allow` applies it silently.
class RecordStockMovement {
  const RecordStockMovement({
    required StockMovementIdGenerator idGenerator,
    required StockMovementRepository movementRepository,
    required BranchStockRepository branchStockRepository,
    required InventoryItemRepository inventoryItemRepository,
    required InventoryAuditEntryRepository auditRepository,
    StockLotRepository? lotRepository,
  })  : _idGenerator = idGenerator,
        _movementRepository = movementRepository,
        _branchStockRepository = branchStockRepository,
        _inventoryItemRepository = inventoryItemRepository,
        _auditRepository = auditRepository,
        _lotRepository = lotRepository;

  final StockMovementIdGenerator _idGenerator;
  final StockMovementRepository _movementRepository;
  final BranchStockRepository _branchStockRepository;
  final InventoryItemRepository _inventoryItemRepository;
  final InventoryAuditEntryRepository _auditRepository;
  final StockLotRepository? _lotRepository;

  Future<BranchStock> call({
    required String branchId,
    required String inventoryItemId,
    required String locationId,
    required StockMovementType type,
    required Quantity quantityDelta,
    String? lotId,
    String? relatedOrderId,
    String? relatedPurchaseOrderId,
    String? reason,
    required String idempotencyKey,
    required String performedByStaffId,
    required DateTime occurredAt,
    String? correlationId,
  }) async {
    final existingMovement =
        await _movementRepository.findByIdempotencyKey(idempotencyKey);
    if (existingMovement != null) {
      final existingBalance = await _branchStockRepository
          .findByItemAndLocation(inventoryItemId, locationId);
      if (existingBalance != null) return existingBalance;
    }

    final inventoryItem =
        await _inventoryItemRepository.findById(inventoryItemId);
    if (inventoryItem == null) {
      throw UnknownInventoryEntityViolation(
        entityName: 'InventoryItem',
        id: inventoryItemId,
      );
    }

    final existingBalance = await _branchStockRepository.findByItemAndLocation(
        inventoryItemId, locationId);
    final currentQuantity =
        existingBalance?.quantityOnHand ?? Quantity.zero(quantityDelta.unit);
    final newQuantity = currentQuantity + quantityDelta;

    var isWarning = false;
    if (newQuantity.isNegative) {
      switch (inventoryItem.negativeStockPolicy) {
        case NegativeStockPolicy.forbid:
          throw NegativeStockNotAllowedViolation(
            inventoryItemId: inventoryItemId,
            locationId: locationId,
          );
        case NegativeStockPolicy.warn:
          isWarning = true;
        case NegativeStockPolicy.allow:
          break;
      }
    }

    final movement = StockMovement(
      id: _idGenerator.nextStockMovementId(),
      branchId: branchId,
      inventoryItemId: inventoryItemId,
      locationId: locationId,
      type: type,
      quantityDelta: quantityDelta,
      lotId: lotId,
      relatedOrderId: relatedOrderId,
      relatedPurchaseOrderId: relatedPurchaseOrderId,
      reason: reason,
      idempotencyKey: idempotencyKey,
      performedByStaffId: performedByStaffId,
      occurredAt: occurredAt,
      correlationId: correlationId,
    );
    await _movementRepository.append(movement);

    if (lotId != null && _lotRepository != null) {
      final lot = await _lotRepository.findById(lotId);
      if (lot != null) {
        await _lotRepository.save(
          lot.copyWith(
              quantityRemaining: lot.quantityRemaining + quantityDelta),
        );
      }
    }

    final updatedBalance = BranchStock(
      inventoryItemId: inventoryItemId,
      locationId: locationId,
      branchId: branchId,
      quantityOnHand: newQuantity,
      isNegativeStockWarning: isWarning,
      lastMovementId: movement.id,
      updatedAt: occurredAt,
    );
    await _branchStockRepository.save(updatedBalance);

    await _auditRepository.appendEvent(InventoryAuditEntry(
      id: '${movement.id}-audit',
      branchId: branchId,
      actorId: performedByStaffId,
      type: InventoryAuditEventType.stockMovementRecorded,
      description: '${type.name} of $quantityDelta for "$inventoryItemId" at '
          '"$locationId"',
      targetEntityId: inventoryItemId,
      timestamp: occurredAt,
    ));

    return updatedBalance;
  }
}
