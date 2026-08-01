import '../../../../core/errors/business_rule_violation.dart';
import '../../../crm/data/customer_repository.dart';
import '../../../crm/domain/segmentation/customer.dart';
import '../../../crm/domain/segmentation/customer_account_status.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';

/// Restricts or reinstates a CRM `Customer` account — manager-authorized
/// (`PosAuthorizedAction.manageCustomerAccountStatus`). Lives in
/// `features/admin` (not `features/crm`) since account restriction is an
/// admin-platform action on a CRM entity, not a CRM-domain concept
/// itself — `features/admin` depends on `features/crm`, never the
/// reverse, consistent with every other admin-shell screen already
/// importing CRM screens directly (Phase 6, `docs/decisions.md`
/// ADR-023).
class SetCustomerAccountStatus {
  const SetCustomerAccountStatus({
    required PosAuthorizationPolicy authorizationPolicy,
    required CustomerRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final CustomerRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<Customer> call({
    required String customerId,
    required CustomerAccountStatus newStatus,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageCustomerAccountStatus;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findById(customerId);
    if (existing == null) {
      throw UnknownAdminEntityViolation(entityName: 'Customer', id: customerId);
    }

    final updated = existing.copyWith(
      accountStatus: newStatus,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$customerId-audit-account-status-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: AdminAuditEventType.customerAccountStatusChanged,
      description: 'Customer account status changed to "${newStatus.name}"',
      targetEntityId: customerId,
      previousStateName: existing.accountStatus.name,
      newStateName: newStatus.name,
      timestamp: performedAt,
    ));

    return updated;
  }
}
