import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/staff_member_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/staff/staff_member.dart';

/// Grants a [StaffMember] access to [organizationId] — Phase 8
/// (`docs/decisions.md` ADR-025), tenantOwner-authorized
/// (`PosAuthorizedAction.manageStaffOrganizationAccess`), one tier more
/// sensitive than [GrantStaffBranchAccess]'s manager-tier check, since
/// this is the tenant boundary itself. "Cross-tenant access must
/// require explicit authorization": before this call, [organizationId]
/// is simply absent from [StaffMember.organizationAccess] — deny by
/// omission, not an explicit block.
class GrantStaffOrganizationAccess {
  const GrantStaffOrganizationAccess({
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
    required String organizationId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageStaffOrganizationAccess;
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

    final updated = existing.copyWith(
      organizationAccess: {...existing.organizationAccess, organizationId},
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$staffMemberId-audit-org-granted-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: AdminAuditEventType.staffOrganizationAccessGranted,
      description:
          'Organization access to "$organizationId" granted to $staffMemberId',
      targetEntityId: staffMemberId,
      newStateName: organizationId,
      timestamp: performedAt,
    ));

    return updated;
  }
}
