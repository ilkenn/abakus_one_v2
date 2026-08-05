import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/identity/staff_member_id_generator.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/bootstrap_first_admin_account.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/services/auth/fake_email_password_auth_client.dart';

void main() {
  group('BootstrapFirstAdminAccount', () {
    test(
        'creates the first staff member with the admin role when the '
        'registry is empty', () async {
      final repository = InMemoryStaffMemberRepository();
      final useCase = BootstrapFirstAdminAccount(
        idGenerator: SequentialStaffMemberIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
        authClient: FakeEmailPasswordAuthClient(),
      );

      final member = await useCase(
        displayName: 'İlk Yönetici',
        organizationId: 'org-1',
        createdAt: DateTime(2026, 1, 1),
        email: 'admin@abakus.test',
        password: 'S3curePass!',
      );

      expect(member.roles, {StaffRole.admin});
      expect(member.authUid, isNotNull);
      expect(await repository.findAll(), [member]);
    });

    test('throws once at least one staff member already exists', () async {
      final repository = InMemoryStaffMemberRepository();
      final useCase = BootstrapFirstAdminAccount(
        idGenerator: SequentialStaffMemberIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
        authClient: FakeEmailPasswordAuthClient(),
      );

      await useCase(
        displayName: 'İlk Yönetici',
        organizationId: 'org-1',
        createdAt: DateTime(2026, 1, 1),
        email: 'admin@abakus.test',
        password: 'S3curePass!',
      );

      expect(
        () => useCase(
          displayName: 'İkinci Yönetici',
          organizationId: 'org-1',
          createdAt: DateTime(2026, 1, 2),
          email: 'admin2@abakus.test',
          password: 'S3curePass!',
        ),
        throwsA(isA<AdminPlatformAlreadyBootstrappedViolation>()),
      );
    });

    test('audits the bootstrap with the "system" sentinel actor', () async {
      final repository = InMemoryStaffMemberRepository();
      final auditRepository = InMemoryAdminAuditEntryRepository();
      final useCase = BootstrapFirstAdminAccount(
        idGenerator: SequentialStaffMemberIdGenerator(),
        repository: repository,
        auditRepository: auditRepository,
        authClient: FakeEmailPasswordAuthClient(),
      );

      final member = await useCase(
        displayName: 'İlk Yönetici',
        organizationId: 'org-1',
        createdAt: DateTime(2026, 1, 1),
        email: 'admin@abakus.test',
        password: 'S3curePass!',
      );

      final entries = await auditRepository.findByTargetEntityId(member.id);
      expect(entries.single.actorId, 'system');
    });
  });
}
