import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/staff_member_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/staff/staff_member.dart';

/// The revoke-side sibling of [GrantStaffBranchAccess]. A no-op (no
/// event recorded) if [branchId] wasn't granted in the first place.
class RevokeStaffBranchAccess {
  const RevokeStaffBranchAccess({
    required PosAuthorizationPolicy authorizationPolicy,
    required StaffMemberRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StaffMemberRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<StaffMember> call({
    required String staffMemberId,
    required String branchId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageStaffBranchAccess;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findById(staffMemberId);
    if (existing == null) {
      throw UnknownAdminEntityViolation(
        entityName: 'StaffMember',
        id: staffMemberId,
      );
    }
    if (!existing.branchAccess.contains(branchId)) return existing;

    final updated = existing.copyWith(
      branchAccess: {...existing.branchAccess}..remove(branchId),
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$staffMemberId-audit-branch-revoked-${performedAt.microsecondsSinceEpoch}',
      branchId: branchId,
      actorId: performedByStaffId,
      type: AdminAuditEventType.staffBranchAccessRevoked,
      description: 'Branch access to "$branchId" revoked from $staffMemberId',
      targetEntityId: staffMemberId,
      previousStateName: branchId,
      timestamp: performedAt,
    ));

    return updated;
  }
}
