import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/staff_member_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/staff/staff_member.dart';
import '../identity/staff_member_id_generator.dart';

/// An administrator registers a new [StaffMember] — admin-only
/// (`PosAuthorizedAction.manageStaffAccounts`). Starts with **no roles at
/// all** — a separate `AssignStaffRole` call is required before the new
/// member can sign in (`DevelopmentStaffAuthRepository.signIn` denies an
/// empty-roles member), so account creation and role granting are always
/// two distinct, separately-audited actions.
class RegisterStaffMember {
  const RegisterStaffMember({
    required PosAuthorizationPolicy authorizationPolicy,
    required StaffMemberIdGenerator idGenerator,
    required StaffMemberRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StaffMemberIdGenerator _idGenerator;
  final StaffMemberRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<StaffMember> call({
    required String displayName,
    required String performedByStaffId,
    required DateTime createdAt,
  }) async {
    const action = PosAuthorizedAction.manageStaffAccounts;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final member = StaffMember(
      id: _idGenerator.nextStaffMemberId(),
      displayName: displayName,
      createdAt: createdAt,
      revision: 1,
    );
    await _repository.save(member);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '${member.id}-audit-registered',
      actorId: performedByStaffId,
      type: AdminAuditEventType.staffMemberRegistered,
      description: 'Staff member registered: "$displayName"',
      targetEntityId: member.id,
      timestamp: createdAt,
    ));

    return member;
  }
}
