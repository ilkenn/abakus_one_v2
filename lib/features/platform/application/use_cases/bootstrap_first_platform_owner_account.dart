import '../../../../core/errors/business_rule_violation.dart';
import '../../data/platform_audit_entry_repository.dart';
import '../../data/platform_member_repository.dart';
import '../../domain/audit/platform_audit_entry.dart';
import '../../domain/audit/platform_audit_event_type.dart';
import '../../domain/authorization/platform_role.dart';
import '../../domain/member/platform_member.dart';
import '../identity/platform_member_id_generator.dart';

/// The platform-hierarchy mirror of `BootstrapFirstAdminAccount` — Phase
/// 8 (`docs/decisions.md` ADR-025). The classic bootstrapping problem
/// one level up: the very first [PlatformRole.platformOwner] account has
/// no existing platform owner to authorize it. Creates exactly one
/// [PlatformMember] with [PlatformRole.platformOwner], and only when
/// [PlatformMemberRepository.findAll] is currently empty; every call
/// after the first throws [PlatformAlreadyBootstrappedViolation]. The
/// audited actor is `'system'`, the same sentinel
/// `BootstrapFirstAdminAccount` uses.
class BootstrapFirstPlatformOwnerAccount {
  const BootstrapFirstPlatformOwnerAccount({
    required PlatformMemberIdGenerator idGenerator,
    required PlatformMemberRepository repository,
    required PlatformAuditEntryRepository auditRepository,
  })  : _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PlatformMemberIdGenerator _idGenerator;
  final PlatformMemberRepository _repository;
  final PlatformAuditEntryRepository _auditRepository;

  Future<PlatformMember> call({
    required String displayName,
    required DateTime createdAt,
  }) async {
    final existing = await _repository.findAll();
    if (existing.isNotEmpty) {
      throw const PlatformAlreadyBootstrappedViolation();
    }

    final member = PlatformMember(
      id: _idGenerator.nextPlatformMemberId(),
      displayName: displayName,
      roles: const {PlatformRole.platformOwner},
      createdAt: createdAt,
      revision: 1,
    );
    await _repository.save(member);

    await _auditRepository.appendEvent(PlatformAuditEntry(
      id: '${member.id}-audit-bootstrap',
      actorId: 'system',
      type: PlatformAuditEventType.platformOwnerBootstrapped,
      description: 'First platform owner account bootstrapped: "$displayName"',
      targetEntityId: member.id,
      timestamp: createdAt,
    ));

    return member;
  }
}
