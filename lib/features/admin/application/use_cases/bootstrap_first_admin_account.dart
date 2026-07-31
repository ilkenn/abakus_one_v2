import '../../../../core/errors/business_rule_violation.dart';
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
class BootstrapFirstAdminAccount {
  const BootstrapFirstAdminAccount({
    required StaffMemberIdGenerator idGenerator,
    required StaffMemberRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final StaffMemberIdGenerator _idGenerator;
  final StaffMemberRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<StaffMember> call({
    required String displayName,
    required DateTime createdAt,
  }) async {
    final existing = await _repository.findAll();
    if (existing.isNotEmpty) {
      throw const AdminPlatformAlreadyBootstrappedViolation();
    }

    final member = StaffMember(
      id: _idGenerator.nextStaffMemberId(),
      displayName: displayName,
      roles: const {StaffRole.admin},
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
