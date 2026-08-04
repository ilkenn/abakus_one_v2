import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/platform/application/identity/platform_member_id_generator.dart';
import 'package:abakus_one_v2/features/platform/application/use_cases/bootstrap_first_platform_owner_account.dart';
import 'package:abakus_one_v2/features/platform/data/platform_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/platform/data/platform_member_repository.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BootstrapFirstPlatformOwnerAccount', () {
    test(
        'creates the first platform member with the platformOwner role '
        'when the registry is empty', () async {
      final repository = InMemoryPlatformMemberRepository();
      final useCase = BootstrapFirstPlatformOwnerAccount(
        idGenerator: SequentialPlatformMemberIdGenerator(),
        repository: repository,
        auditRepository: InMemoryPlatformAuditEntryRepository(),
      );

      final member = await useCase(
        displayName: 'İlk Platform Sahibi',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(member.roles, {PlatformRole.platformOwner});
      expect(await repository.findAll(), [member]);
    });

    test('throws once at least one platform member already exists', () async {
      final repository = InMemoryPlatformMemberRepository();
      final useCase = BootstrapFirstPlatformOwnerAccount(
        idGenerator: SequentialPlatformMemberIdGenerator(),
        repository: repository,
        auditRepository: InMemoryPlatformAuditEntryRepository(),
      );

      await useCase(
        displayName: 'İlk Platform Sahibi',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(
        () => useCase(
          displayName: 'İkinci Platform Sahibi',
          createdAt: DateTime(2026, 1, 2),
        ),
        throwsA(isA<PlatformAlreadyBootstrappedViolation>()),
      );
    });

    test('audits the bootstrap with the "system" sentinel actor', () async {
      final repository = InMemoryPlatformMemberRepository();
      final auditRepository = InMemoryPlatformAuditEntryRepository();
      final useCase = BootstrapFirstPlatformOwnerAccount(
        idGenerator: SequentialPlatformMemberIdGenerator(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final member = await useCase(
        displayName: 'İlk Platform Sahibi',
        createdAt: DateTime(2026, 1, 1),
      );

      final entries = await auditRepository.findByTargetEntityId(member.id);
      expect(entries.single.actorId, 'system');
    });
  });
}
