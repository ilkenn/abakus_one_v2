import '../../../../core/errors/business_rule_violation.dart';
import '../../../inventory/application/use_cases/record_stock_movement.dart';
import '../../../inventory/data/stock_movement_repository.dart';
import '../../../inventory/domain/stock_movement_type.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/stock_consumption_audit_entry_repository.dart';
import '../../data/stock_consumption_record_repository.dart';
import '../../domain/stock_consumption_audit_entry.dart';
import '../../domain/stock_consumption_audit_event_type.dart';
import '../../domain/stock_consumption_record.dart';

/// Explicitly reverses a previously-consumed order line's stock —
/// manager+ (`PosAuthorizedAction.recordStockMovement`, the same
/// manual-correction tier `RecordManualStockMovement` uses), Phase 7
/// (`docs/decisions.md` ADR-024).
///
/// **Must be called deliberately, never automatically from a refund
/// event** — "financial refund doesn't imply physical restoration."
/// A customer being refunded does not mean the food itself still
/// exists to put back on the shelf; only call this when a manager has
/// verified the ingredients were genuinely never used (failed
/// preparation caught before cooking, a kitchen error, a legitimate
/// remake credit) — [reason] is required and audited for exactly this
/// reason.
///
/// Append-only, like every other stock write in this codebase: issues
/// new, equal-and-opposite [StockMovementType.reversal] movements
/// (one per original ingredient movement, found via
/// [StockConsumptionRecord.ingredientIdempotencyKeys]) rather than
/// editing or deleting the original consumption movements. A record
/// may only be reversed once — [StockConsumptionAlreadyReversedViolation].
class ReverseStockConsumption {
  const ReverseStockConsumption({
    required PosAuthorizationPolicy authorizationPolicy,
    required StockMovementRepository movementRepository,
    required RecordStockMovement recordStockMovement,
    required StockConsumptionRecordRepository recordRepository,
    required StockConsumptionAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _movementRepository = movementRepository,
        _recordStockMovement = recordStockMovement,
        _recordRepository = recordRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StockMovementRepository _movementRepository;
  final RecordStockMovement _recordStockMovement;
  final StockConsumptionRecordRepository _recordRepository;
  final StockConsumptionAuditEntryRepository _auditRepository;

  Future<StockConsumptionRecord> call({
    required String orderLineId,
    required String reason,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.recordStockMovement;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    if (reason.trim().isEmpty) {
      throw const InventoryReasonRequiredViolation();
    }

    final record = await _recordRepository.findByOrderLineId(orderLineId);
    if (record == null) {
      throw UnknownStockConsumptionEntityViolation(
        entityName: 'StockConsumptionRecord',
        id: orderLineId,
      );
    }
    if (record.reversedAt != null) {
      throw StockConsumptionAlreadyReversedViolation(recordId: record.id);
    }

    for (final ingredientKey in record.ingredientIdempotencyKeys) {
      final originalMovement =
          await _movementRepository.findByIdempotencyKey(ingredientKey);
      if (originalMovement == null) continue;

      await _recordStockMovement(
        branchId: originalMovement.branchId,
        inventoryItemId: originalMovement.inventoryItemId,
        locationId: originalMovement.locationId,
        type: StockMovementType.reversal,
        quantityDelta: -originalMovement.quantityDelta,
        relatedOrderId: originalMovement.relatedOrderId,
        reason: reason,
        idempotencyKey: '$ingredientKey-reversal',
        performedByStaffId: performedByStaffId,
        occurredAt: performedAt,
        correlationId: orderLineId,
      );
    }

    final reversed = record.copyWith(reversedAt: performedAt);
    await _recordRepository.save(reversed);

    await _auditRepository.appendEvent(StockConsumptionAuditEntry(
      id: '${record.id}-audit-reversed',
      branchId: record.branchId,
      actorId: performedByStaffId,
      type: StockConsumptionAuditEventType.orderLineConsumptionReversed,
      description:
          'Stock consumption reversed for order line "$orderLineId": $reason',
      targetEntityId: record.id,
      timestamp: performedAt,
    ));

    return reversed;
  }
}
