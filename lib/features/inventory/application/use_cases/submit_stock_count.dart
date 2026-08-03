import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/inventory_audit_entry_repository.dart';
import '../../data/stock_count_repository.dart';
import '../../domain/inventory_audit_entry.dart';
import '../../domain/inventory_audit_event_type.dart';
import '../../domain/stock_count.dart';

/// Submits an in-progress [StockCount] for manager review — staff+
/// (`PosAuthorizedAction.recordStockCount`), Phase 7
/// (`docs/decisions.md` ADR-024). A submitted count is never editable
/// again — see `StockCount`'s own doc comment.
class SubmitStockCount {
  const SubmitStockCount({
    required PosAuthorizationPolicy authorizationPolicy,
    required StockCountRepository repository,
    required InventoryAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StockCountRepository _repository;
  final InventoryAuditEntryRepository _auditRepository;

  Future<StockCount> call({
    required String countId,
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

    const action = PosAuthorizedAction.recordStockCount;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: count.branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    if (count.status != StockCountStatus.inProgress) {
      throw InvalidInventoryWorkflowTransitionViolation(
        fromStatusName: count.status.name,
        toStatusName: StockCountStatus.submitted.name,
      );
    }

    final updated = count.copyWith(
      status: StockCountStatus.submitted,
      submittedAt: performedAt,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(InventoryAuditEntry(
      id: '${count.id}-audit-submitted',
      branchId: count.branchId,
      actorId: performedByStaffId,
      type: InventoryAuditEventType.stockCountSubmitted,
      description: 'Stock count "${count.id}" submitted for review',
      targetEntityId: count.id,
      timestamp: performedAt,
    ));

    return updated;
  }
}
