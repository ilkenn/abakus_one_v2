import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/identity/staff_member_id_generator.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/bootstrap_first_admin_account.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

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
      );

      final member = await useCase(
        displayName: 'İlk Yönetici',
        organizationId: 'org-1',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(member.roles, {StaffRole.admin});
      expect(await repository.findAll(), [member]);
    });

    test('throws once at least one staff member already exists', () async {
      final repository = InMemoryStaffMemberRepository();
      final useCase = BootstrapFirstAdminAccount(
        idGenerator: SequentialStaffMemberIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      await useCase(
        displayName: 'İlk Yönetici',
        organizationId: 'org-1',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(
        () => useCase(
          displayName: 'İkinci Yönetici',
          organizationId: 'org-1',
          createdAt: DateTime(2026, 1, 2),
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
      );

      final member = await useCase(
        displayName: 'İlk Yönetici',
        organizationId: 'org-1',
        createdAt: DateTime(2026, 1, 1),
      );

      final entries = await auditRepository.findByTargetEntityId(member.id);
      expect(entries.single.actorId, 'system');
    });
  });
}
