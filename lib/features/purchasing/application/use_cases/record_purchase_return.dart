import '../../../../core/errors/business_rule_violation.dart';
import '../../../inventory/domain/quantity.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/purchase_return_repository.dart';
import '../../data/supplier_audit_entry_repository.dart';
import '../../domain/purchase_return.dart';
import '../../domain/supplier_audit_entry.dart';
import '../../domain/supplier_audit_event_type.dart';
import '../identity/purchase_return_id_generator.dart';

/// Records a [PurchaseReturn] against a specific [GoodsReceiptLine] —
/// manager+ (`PosAuthorizedAction.managePurchasing`), Phase 7
/// (`docs/decisions.md` ADR-024). [reason] is required, matching every
/// other reason-requiring correction in Phase 7. No accounting/
/// e-invoice integration — purely an operational record (explicit
/// out-of-scope per the Phase 7 kickoff).
class RecordPurchaseReturn {
  const RecordPurchaseReturn({
    required PosAuthorizationPolicy authorizationPolicy,
    required PurchaseReturnIdGenerator idGenerator,
    required PurchaseReturnRepository repository,
    required SupplierAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final PurchaseReturnIdGenerator _idGenerator;
  final PurchaseReturnRepository _repository;
  final SupplierAuditEntryRepository _auditRepository;

  Future<PurchaseReturn> call({
    required String organizationId,
    required String branchId,
    required String supplierId,
    required String goodsReceiptLineId,
    required Quantity returnedQuantity,
    required String reason,
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

    if (reason.trim().isEmpty) {
      throw const InventoryReasonRequiredViolation();
    }

    final purchaseReturn = PurchaseReturn(
      id: _idGenerator.nextPurchaseReturnId(),
      organizationId: organizationId,
      branchId: branchId,
      supplierId: supplierId,
      goodsReceiptLineId: goodsReceiptLineId,
      returnedQuantity: returnedQuantity,
      reason: reason,
      createdByStaffId: performedByStaffId,
      createdAt: performedAt,
    );
    await _repository.save(purchaseReturn);

    await _auditRepository.appendEvent(SupplierAuditEntry(
      id: '${purchaseReturn.id}-audit-recorded',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: SupplierAuditEventType.purchaseReturnRecorded,
      description: 'Purchase return recorded for receipt line '
          '"$goodsReceiptLineId": $reason',
      targetEntityId: purchaseReturn.id,
      timestamp: performedAt,
    ));

    return purchaseReturn;
  }
}
