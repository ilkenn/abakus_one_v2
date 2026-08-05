import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/platform/application/identity/platform_member_id_generator.dart';
import 'package:abakus_one_v2/features/platform/application/use_cases/bootstrap_first_platform_owner_account.dart';
import 'package:abakus_one_v2/features/platform/data/platform_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/platform/data/platform_member_repository.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_role.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/services/auth/fake_email_password_auth_client.dart';

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
        authClient: FakeEmailPasswordAuthClient(),
      );

      final member = await useCase(
        displayName: 'İlk Platform Sahibi',
        createdAt: DateTime(2026, 1, 1),
        email: 'owner@abakus.test',
        password: 'S3curePass!',
      );

      expect(member.roles, {PlatformRole.platformOwner});
      expect(member.authUid, isNotNull);
      expect(await repository.findAll(), [member]);
    });

    test('throws once at least one platform member already exists', () async {
      final repository = InMemoryPlatformMemberRepository();
      final useCase = BootstrapFirstPlatformOwnerAccount(
        idGenerator: SequentialPlatformMemberIdGenerator(),
        repository: repository,
        auditRepository: InMemoryPlatformAuditEntryRepository(),
        authClient: FakeEmailPasswordAuthClient(),
      );

      await useCase(
        displayName: 'İlk Platform Sahibi',
        createdAt: DateTime(2026, 1, 1),
        email: 'owner@abakus.test',
        password: 'S3curePass!',
      );

      expect(
        () => useCase(
          displayName: 'İkinci Platform Sahibi',
          createdAt: DateTime(2026, 1, 2),
          email: 'owner2@abakus.test',
          password: 'S3curePass!',
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
        authClient: FakeEmailPasswordAuthClient(),
      );

      final member = await useCase(
        displayName: 'İlk Platform Sahibi',
        createdAt: DateTime(2026, 1, 1),
        email: 'owner@abakus.test',
        password: 'S3curePass!',
      );

      final entries = await auditRepository.findByTargetEntityId(member.id);
      expect(entries.single.actorId, 'system');
    });
  });
}
