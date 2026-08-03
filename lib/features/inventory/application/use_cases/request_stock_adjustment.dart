import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/stock_adjustment_repository.dart';
import '../../domain/inventory_audit_entry.dart';
import '../../domain/inventory_audit_event_type.dart';
import '../../data/inventory_audit_entry_repository.dart';
import '../../domain/quantity.dart';
import '../../domain/stock_adjustment.dart';
import '../identity/stock_adjustment_id_generator.dart';

/// Requests a manual stock correction — staff+ (any staff-tier actor
/// may request one; only a manager can approve it, see
/// `ApproveStockAdjustment`). [reason] must be non-empty — "waste
/// requires reason," extended to every manual adjustment. Reuses
/// `PosAuthorizedAction.recordStockCount` (staff-tier) rather than
/// adding yet another near-duplicate action — requesting an adjustment
/// is the same "front-line staff flags a discrepancy" act a stock count
/// already covers.
class RequestStockAdjustment {
  const RequestStockAdjustment({
    required PosAuthorizationPolicy authorizationPolicy,
    required StockAdjustmentIdGenerator idGenerator,
    required StockAdjustmentRepository repository,
    required InventoryAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StockAdjustmentIdGenerator _idGenerator;
  final StockAdjustmentRepository _repository;
  final InventoryAuditEntryRepository _auditRepository;

  Future<StockAdjustment> call({
    required String branchId,
    required String inventoryItemId,
    required String locationId,
    required Quantity quantityDelta,
    required String reason,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    if (reason.trim().isEmpty) {
      throw const InventoryReasonRequiredViolation();
    }

    const action = PosAuthorizedAction.recordStockCount;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final adjustment = StockAdjustment(
      id: _idGenerator.nextStockAdjustmentId(),
      branchId: branchId,
      inventoryItemId: inventoryItemId,
      locationId: locationId,
      quantityDelta: quantityDelta,
      reason: reason,
      requestedByStaffId: performedByStaffId,
      createdAt: performedAt,
    );
    await _repository.save(adjustment);

    await _auditRepository.appendEvent(InventoryAuditEntry(
      id: '${adjustment.id}-audit-requested',
      branchId: branchId,
      actorId: performedByStaffId,
      type: InventoryAuditEventType.stockAdjustmentRequested,
      description: 'Stock adjustment requested: $quantityDelta ($reason)',
      targetEntityId: adjustment.id,
      timestamp: performedAt,
    ));

    return adjustment;
  }
}
