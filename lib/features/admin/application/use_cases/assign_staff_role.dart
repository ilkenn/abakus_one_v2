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

/// An administrator/manager grants [role] to an existing [StaffMember] —
/// "a user may hold multiple roles," so this only ever adds to the
/// existing set, never replaces it.
///
/// **Authorization is role-scoped**: granting [StaffRole.admin] requires
/// `PosAuthorizedAction.manageStaffAdminRole` (admin-only — "no manager
/// granting admin unless authorized"); granting anything else requires
/// only `PosAuthorizedAction.manageStaffRoles` (manager+).
///
/// **"No self-promotion"** is enforced structurally, before the
/// authorization check even runs — an admin granting themselves a role
/// they don't yet hold is blocked exactly the same way a manager
/// attempting the same thing would be, regardless of what the
/// authorization policy would otherwise allow.
class AssignStaffRole {
  const AssignStaffRole({
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
    if (!existing.isActive) {
      throw StaffMemberNotActiveViolation(staffMemberId: staffMemberId);
    }

    final updated = existing.copyWith(
      roles: {...existing.roles, role},
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _roleChangeEventRepository.append(StaffRoleChangeEvent(
      id: _idGenerator.nextEventId(),
      staffMemberId: staffMemberId,
      changeType: StaffRoleChangeType.granted,
      role: role,
      performedByStaffId: performedByStaffId,
      occurredAt: performedAt,
    ));

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$staffMemberId-audit-role-granted-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: AdminAuditEventType.staffRoleGranted,
      description: 'Role "${role.name}" granted to $staffMemberId',
      targetEntityId: staffMemberId,
      newStateName: role.name,
      timestamp: performedAt,
    ));

    return updated;
  }
}
