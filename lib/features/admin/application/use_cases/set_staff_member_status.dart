import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/staff_member_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/staff/staff_member.dart';
import '../../domain/staff/staff_member_status.dart';

/// Suspends, reinstates, or archives a [StaffMember] — admin-only
/// (`PosAuthorizedAction.manageStaffAccounts`). `active <-> suspended`
/// is reversible; `-> archived` is terminal — an already-[StaffMemberStatus
/// .archived] member can never be targeted again, matching the domain
/// distinction [StaffMemberStatus]'s own doc comment draws. A suspended
/// or archived member immediately fails `StaffAuthRepository.signIn`
/// (and `refreshSession`, for anyone with an existing session) — no
/// separate "kick out" step is needed.
class SetStaffMemberStatus {
  const SetStaffMemberStatus({
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
    required StaffMemberStatus newStatus,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageStaffAccounts;
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
    if (existing.status == StaffMemberStatus.archived) {
      throw StaffMemberArchivedViolation(staffMemberId: staffMemberId);
    }

    final updated = existing.copyWith(
      status: newStatus,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$staffMemberId-audit-status-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: switch (newStatus) {
        StaffMemberStatus.active => AdminAuditEventType.staffMemberReinstated,
        StaffMemberStatus.suspended => AdminAuditEventType.staffMemberSuspended,
        StaffMemberStatus.archived => AdminAuditEventType.staffMemberArchived,
      },
      description: 'Staff member status changed to "${newStatus.name}"',
      targetEntityId: staffMemberId,
      previousStateName: existing.status.name,
      newStateName: newStatus.name,
      timestamp: performedAt,
    ));

    return updated;
  }
}
