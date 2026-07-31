import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/staff_role.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/staff_member_repository.dart';
import '../../data/staff_role_change_event_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/staff/staff_member.dart';
import '../../domain/staff/staff_role_change_event.dart';
import '../identity/staff_role_change_event_id_generator.dart';

/// The revoke-side sibling of [AssignStaffRole] — same self-revocation
/// guard (a staff member cannot remove their own role either, avoiding
/// an accidental or malicious self-lockout-then-reclaim), same
/// role-scoped authorization (revoking `StaffRole.admin` requires
/// `manageStaffAdminRole`; anything else requires `manageStaffRoles`).
/// If [role] is not currently held, this is a no-op — [StaffMember.roles]
/// already didn't contain it, so nothing changes and no event is
/// recorded (an audit log records real state changes only, mirroring
/// `GrantVisitReward`'s "only on an actual grant" rule).
class RevokeStaffRole {
  const RevokeStaffRole({
    required PosAuthorizationPolicy authorizationPolicy,
    required StaffMemberRepository repository,
    required StaffRoleChangeEventRepository roleChangeEventRepository,
    required StaffRoleChangeEventIdGenerator idGenerator,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _roleChangeEventRepository = roleChangeEventRepository,
        _idGenerator = idGenerator,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StaffMemberRepository _repository;
  final StaffRoleChangeEventRepository _roleChangeEventRepository;
  final StaffRoleChangeEventIdGenerator _idGenerator;
  final AdminAuditEntryRepository _auditRepository;

  Future<StaffMember> call({
    required String staffMemberId,
    required StaffRole role,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    if (staffMemberId == performedByStaffId) {
      throw SelfRoleGrantNotAllowedViolation(staffMemberId: staffMemberId);
    }

    final action = role == StaffRole.admin
        ? PosAuthorizedAction.manageStaffAdminRole
        : PosAuthorizedAction.manageStaffRoles;
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
    if (!existing.roles.contains(role)) return existing;

    final updated = existing.copyWith(
      roles: {...existing.roles}..remove(role),
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _roleChangeEventRepository.append(StaffRoleChangeEvent(
      id: _idGenerator.nextEventId(),
      staffMemberId: staffMemberId,
      changeType: StaffRoleChangeType.revoked,
      role: role,
      performedByStaffId: performedByStaffId,
      occurredAt: performedAt,
    ));

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$staffMemberId-audit-role-revoked-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: AdminAuditEventType.staffRoleRevoked,
      description: 'Role "${role.name}" revoked from $staffMemberId',
      targetEntityId: staffMemberId,
      previousStateName: role.name,
      timestamp: performedAt,
    ));

    return updated;
  }
}
