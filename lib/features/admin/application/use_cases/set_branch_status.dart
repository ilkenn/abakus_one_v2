import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/branch_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/organization/branch.dart';
import '../../domain/organization/branch_status.dart';

/// Sets a [Branch]'s [BranchStatus] — admin-only
/// (`PosAuthorizedAction.manageBranch`). `archived` is terminal, mirroring
/// `SetStaffMemberStatus`'s own reversible-vs-terminal rule.
class SetBranchStatus {
  const SetBranchStatus({
    required PosAuthorizationPolicy authorizationPolicy,
    required BranchRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final BranchRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<Branch> call({
    required String branchId,
    required BranchStatus newStatus,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageBranch;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findById(branchId);
    if (existing == null) {
      throw UnknownAdminEntityViolation(entityName: 'Branch', id: branchId);
    }
    if (existing.status == BranchStatus.archived) {
      throw BranchArchivedViolation(branchId: branchId);
    }

    final updated = existing.copyWith(
      status: newStatus,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$branchId-audit-status-${performedAt.microsecondsSinceEpoch}',
      branchId: branchId,
      actorId: performedByStaffId,
      type: AdminAuditEventType.branchStatusChanged,
      description: 'Branch status changed to "${newStatus.name}"',
      targetEntityId: branchId,
      previousStateName: existing.status.name,
      newStateName: newStatus.name,
      timestamp: performedAt,
    ));

    return updated;
  }
}
