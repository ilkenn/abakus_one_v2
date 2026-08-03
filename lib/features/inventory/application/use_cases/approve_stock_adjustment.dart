import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/inventory_audit_entry_repository.dart';
import '../../data/stock_adjustment_repository.dart';
import '../../domain/inventory_audit_entry.dart';
import '../../domain/inventory_audit_event_type.dart';
import '../../domain/stock_adjustment.dart';
import '../../domain/stock_movement_type.dart';
import 'record_stock_movement.dart';

/// Approves or rejects a [StockAdjustment] — manager+
/// (`PosAuthorizedAction.approveStockCountAdjustment`). "Cashier/
/// counter cannot approve their own material variance" — throws
/// [SelfApprovalNotAllowedViolation] when the approver is the same
/// staff member who requested it, checked *before* the authorization
/// call, holding regardless of role. Approving produces a real
/// `StockMovement` (`StockMovementType.adjustment`); rejecting never
/// touches stock at all.
class ApproveStockAdjustment {
  const ApproveStockAdjustment({
    required PosAuthorizationPolicy authorizationPolicy,
    required StockAdjustmentRepository repository,
    required RecordStockMovement recordStockMovement,
    required InventoryAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _recordStockMovement = recordStockMovement,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StockAdjustmentRepository _repository;
  final RecordStockMovement _recordStockMovement;
  final InventoryAuditEntryRepository _auditRepository;

  Future<StockAdjustment> call({
    required String adjustmentId,
    required bool approve,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    final adjustment = await _repository.findById(adjustmentId);
    if (adjustment == null) {
      throw UnknownInventoryEntityViolation(
        entityName: 'StockAdjustment',
        id: adjustmentId,
      );
    }

    if (adjustment.requestedByStaffId == performedByStaffId) {
      throw SelfApprovalNotAllowedViolation(staffId: performedByStaffId);
    }

    if (adjustment.status != StockAdjustmentStatus.pending) {
      throw InvalidInventoryWorkflowTransitionViolation(
        fromStatusName: adjustment.status.name,
        toStatusName: approve ? 'approved' : 'rejected',
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

    final updated = adjustment.copyWith(
      status: approve
          ? StockAdjustmentStatus.approved
          : StockAdjustmentStatus.rejected,
      approvedByStaffId: performedByStaffId,
      approvedAt: performedAt,
    );
    await _repository.save(updated);

    if (approve) {
      await _recordStockMovement(
        branchId: adjustment.branchId,
        inventoryItemId: adjustment.inventoryItemId,
        locationId: adjustment.locationId,
        type: StockMovementType.adjustment,
        quantityDelta: adjustment.quantityDelta,
        reason: adjustment.reason,
        idempotencyKey: 'stock-adjustment-${adjustment.id}',
        performedByStaffId: performedByStaffId,
        occurredAt: performedAt,
        correlationId: adjustment.id,
      );
    }

    await _auditRepository.appendEvent(InventoryAuditEntry(
      id: '${adjustment.id}-audit-${approve ? 'approved' : 'rejected'}',
      branchId: adjustment.branchId,
      actorId: performedByStaffId,
      type: approve
          ? InventoryAuditEventType.stockAdjustmentApproved
          : InventoryAuditEventType.stockAdjustmentRejected,
      description: 'Stock adjustment ${approve ? 'approved' : 'rejected'}',
      targetEntityId: adjustment.id,
      timestamp: performedAt,
    ));

    return updated;
  }
}
