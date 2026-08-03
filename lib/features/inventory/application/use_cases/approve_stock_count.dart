import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/inventory_audit_entry_repository.dart';
import '../../data/stock_count_line_repository.dart';
import '../../data/stock_count_repository.dart';
import '../../domain/inventory_audit_entry.dart';
import '../../domain/inventory_audit_event_type.dart';
import '../../domain/stock_count.dart';
import '../../domain/stock_movement_type.dart';
import 'record_stock_movement.dart';

/// A manager reviews a submitted [StockCount] — approving applies a
/// real [StockMovementType.countCorrection] `StockMovement` for every
/// line whose `varianceQuantity` is non-zero, correcting `BranchStock`
/// to match what was actually counted; rejecting touches no stock at
/// all — manager+ (`PosAuthorizedAction.approveStockCountAdjustment`),
/// Phase 7 (`docs/decisions.md` ADR-024).
///
/// "Cashier/counter cannot approve own material variance" —
/// [SelfApprovalNotAllowedViolation] is checked *before* the
/// authorization call, holding regardless of role, exactly like
/// `ApproveStockAdjustment`.
class ApproveStockCount {
  const ApproveStockCount({
    required PosAuthorizationPolicy authorizationPolicy,
    required StockCountRepository repository,
    required StockCountLineRepository lineRepository,
    required RecordStockMovement recordStockMovement,
    required InventoryAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _lineRepository = lineRepository,
        _recordStockMovement = recordStockMovement,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StockCountRepository _repository;
  final StockCountLineRepository _lineRepository;
  final RecordStockMovement _recordStockMovement;
  final InventoryAuditEntryRepository _auditRepository;

  Future<StockCount> call({
    required bool approve,
    required String countId,
    String? rejectionReason,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    final count = await _repository.findById(countId);
    if (count == null) {
      throw UnknownInventoryEntityViolation(
        entityName: 'StockCount',
        id: countId,
      );
    }

    if (count.startedByStaffId == performedByStaffId) {
      throw SelfApprovalNotAllowedViolation(staffId: performedByStaffId);
    }

    if (count.status != StockCountStatus.submitted) {
      throw InvalidInventoryWorkflowTransitionViolation(
        fromStatusName: count.status.name,
        toStatusName: approve
            ? StockCountStatus.approved.name
            : StockCountStatus.rejected.name,
      );
    }

    const action = PosAuthorizedAction.approveStockCountAdjustment;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    if (approve) {
      final lines = await _lineRepository.findByCountId(countId);
      for (final line in lines) {
        if (line.varianceQuantity.isZero) continue;
        await _recordStockMovement(
          branchId: count.branchId,
          inventoryItemId: line.inventoryItemId,
          locationId: count.locationId,
          type: StockMovementType.countCorrection,
          quantityDelta: line.varianceQuantity,
          reason: 'Stok sayımı düzeltmesi (${count.id})',
          idempotencyKey: 'stock-count-${count.id}-${line.inventoryItemId}',
          performedByStaffId: performedByStaffId,
          occurredAt: performedAt,
          correlationId: count.id,
        );
      }
    }

    final updated = count.copyWith(
      status: approve ? StockCountStatus.approved : StockCountStatus.rejected,
      approvedByStaffId: performedByStaffId,
      approvedAt: performedAt,
      rejectionReason: approve ? null : rejectionReason,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(InventoryAuditEntry(
      id: '${count.id}-audit-${approve ? 'approved' : 'rejected'}',
      branchId: count.branchId,
      actorId: performedByStaffId,
      type: approve
          ? InventoryAuditEventType.stockCountApproved
          : InventoryAuditEventType.stockCountRejected,
      description: approve
          ? 'Stock count "${count.id}" approved'
          : 'Stock count "${count.id}" rejected'
              '${rejectionReason != null ? ': $rejectionReason' : ''}',
      targetEntityId: count.id,
      timestamp: performedAt,
    ));

    return updated;
  }
}
