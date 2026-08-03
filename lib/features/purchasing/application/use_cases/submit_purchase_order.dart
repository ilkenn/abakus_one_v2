import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/purchase_order_repository.dart';
import '../../data/supplier_audit_entry_repository.dart';
import '../../domain/purchase_order.dart';
import '../../domain/purchase_order_status.dart';
import '../../domain/supplier_audit_entry.dart';
import '../../domain/supplier_audit_event_type.dart';

/// Transitions a [PurchaseOrder] from [PurchaseOrderStatus.draft] to
/// [PurchaseOrderStatus.submitted] — manager+
/// (`PosAuthorizedAction.managePurchasing`), Phase 7
/// (`docs/decisions.md` ADR-024).
class SubmitPurchaseOrder {
  const SubmitPurchaseOrder({
    required PosAuthorizationPolicy authorizationPolicy,
    required PurchaseOrderRepository repository,
    required SupplierAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final PurchaseOrderRepository _repository;
  final SupplierAuditEntryRepository _auditRepository;

  Future<PurchaseOrder> call({
    required String purchaseOrderId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.managePurchasing;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final order = await _repository.findById(purchaseOrderId);
    if (order == null) {
      throw UnknownSupplierEntityViolation(
        entityName: 'PurchaseOrder',
        id: purchaseOrderId,
      );
    }
    if (order.status != PurchaseOrderStatus.draft) {
      throw InvalidPurchaseOrderTransitionViolation(
        fromStatusName: order.status.name,
        toStatusName: PurchaseOrderStatus.submitted.name,
      );
    }

    final updated = order.copyWith(
      status: PurchaseOrderStatus.submitted,
      submittedAt: performedAt,
      revision: order.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(SupplierAuditEntry(
      id: '${order.id}-audit-submitted',
      organizationId: order.organizationId,
      actorId: performedByStaffId,
      type: SupplierAuditEventType.purchaseOrderSubmitted,
      description: 'Purchase order "${order.id}" submitted',
      targetEntityId: order.id,
      timestamp: performedAt,
    ));

    return updated;
  }
}
