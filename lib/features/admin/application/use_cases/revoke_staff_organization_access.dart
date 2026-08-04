import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/staff_member_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/staff/staff_member.dart';

/// The revoke-side sibling of [GrantStaffOrganizationAccess] — Phase 8
/// (`docs/decisions.md` ADR-025). A no-op (no event recorded) if
/// [organizationId] wasn't granted in the first place.
class RevokeStaffOrganizationAccess {
  const RevokeStaffOrganizationAccess({
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
    if (!existing.organizationAccess.contains(organizationId)) return existing;

    final updated = existing.copyWith(
      organizationAccess: {...existing.organizationAccess}
        ..remove(organizationId),
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$staffMemberId-audit-org-revoked-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: AdminAuditEventType.staffOrganizationAccessRevoked,
      description:
          'Organization access to "$organizationId" revoked from $staffMemberId',
      targetEntityId: staffMemberId,
      previousStateName: organizationId,
      timestamp: performedAt,
    ));

    return updated;
  }
}
