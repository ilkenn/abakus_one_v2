import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/staff_member_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/staff/staff_member.dart';

/// An administrator registers a new [StaffMember] — admin-only
/// (`PosAuthorizedAction.manageStaffAccounts`). Starts with **no roles at
/// all** — a separate `AssignStaffRole` call is required before the new
/// member can sign in (`DevelopmentStaffAuthRepository.signIn` denies an
/// empty-roles member), so account creation and role granting are always
/// two distinct, separately-audited actions.
///
/// **AP-2 Stage B**: [email] is now required — the real backend
/// (`registerStaffMember` Cloud Function) links a new membership to an
/// *existing* Firebase Auth account found by email; a display name alone
/// is no longer sufficient to create a real, sign-in-capable account. See
/// [StaffMemberRepository.register]'s own doc comment. `idGenerator` is no
/// longer a constructor dependency of this use case — id assignment moved
/// into [StaffMemberRepository.register] itself (each real implementation
/// derives its own id: `InMemoryStaffMemberRepository` sequentially,
/// `FirebaseStaffMemberRepository` from the linked Firebase Auth uid).
class RegisterStaffMember {
  const RegisterStaffMember({
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
    required String displayName,
    required String email,
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

    final member = await _repository.register(
      displayName: displayName,
      email: email,
    );

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
