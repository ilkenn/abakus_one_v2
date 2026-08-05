import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/services/auth/email_password_auth_client.dart';
import '../../../pos/domain/authorization/staff_role.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/staff_member_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/staff/staff_member.dart';
import '../identity/staff_member_id_generator.dart';

/// The one deliberate, self-limiting exception to "no manager granting
/// admin unless authorized": every other role grant goes through
/// [AssignStaffRole] and its `manageStaffAdminRole` authorization check,
/// but the very first admin account has no existing admin to authorize
/// it — the classic bootstrapping problem. This use case creates exactly
/// one [StaffMember] with [StaffRole.admin], and only when
/// [StaffMemberRepository.findAll] is currently empty; every call after
/// the first throws [AdminPlatformAlreadyBootstrappedViolation]. The
/// audited actor is `'system'`, the same documented sentinel
/// `RecordCustomerVisitAndEvaluateRewards` uses for its one automated,
/// no-human-actor call site (`docs/decisions.md` ADR-022) — never a
/// hardcoded production identity.
///
/// **Phase 8** (`docs/decisions.md` ADR-025): also grants
/// `organizationAccess: {organizationId}` — since
/// `RealPosAuthorizationPolicy`'s organization-scoping check exempts no
/// role, including admin (unlike the pre-existing branch-scoping
/// exemption), the first bootstrapped admin would otherwise be denied
/// every organization-scoped action immediately after bootstrapping —
/// the same bootstrap paradox `AssignStaffRole` already solves for the
/// admin role itself, resolved here the same way: a caller-supplied
/// value at the one call site that has no prior authority to derive it
/// from.
class BootstrapFirstAdminAccount {
  const BootstrapFirstAdminAccount({
    required StaffMemberIdGenerator idGenerator,
    required StaffMemberRepository repository,
    required AdminAuditEntryRepository auditRepository,
    required EmailPasswordAuthClient authClient,
  })  : _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository,
        _authClient = authClient;

  final StaffMemberIdGenerator _idGenerator;
  final StaffMemberRepository _repository;
  final AdminAuditEntryRepository _auditRepository;
  final EmailPasswordAuthClient _authClient;

  /// [email]/[password] become this account's real, permanent sign-in
  /// credential — Sprint 9C (`docs/decisions.md` ADR-026). Creating the
  /// Firebase Auth account here (rather than requiring one to already
  /// exist) is a deliberate, narrow exception: this is the one
  /// self-service account-creation path in the app, mirroring why the
  /// role-grant itself is self-authorized — there is no existing admin
  /// account to have created this one in advance.
  Future<StaffMember> call({
    required String displayName,
    required String organizationId,
    required DateTime createdAt,
    required String email,
    required String password,
  }) async {
    final existing = await _repository.findAll();
    if (existing.isNotEmpty) {
      throw const AdminPlatformAlreadyBootstrappedViolation();
    }

    final authResult =
        await _authClient.createAccount(email: email, password: password);

    final member = StaffMember(
      id: _idGenerator.nextStaffMemberId(),
      displayName: displayName,
      roles: const {StaffRole.admin},
      organizationAccess: {organizationId},
      authUid: authResult.uid,
      createdAt: createdAt,
      revision: 1,
    );
    await _repository.save(member);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '${member.id}-audit-bootstrap',
      actorId: 'system',
      actorRole: 'system',
      type: AdminAuditEventType.staffMemberRegistered,
      description: 'First admin account bootstrapped: "$displayName"',
      targetEntityId: member.id,
      newStateName: StaffRole.admin.name,
      timestamp: createdAt,
    ));

    return member;
  }
}
