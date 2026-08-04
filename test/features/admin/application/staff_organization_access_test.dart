import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/grant_staff_organization_access.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/revoke_staff_organization_access.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  group('GrantStaffOrganizationAccess', () {
    test('grants organization access, additive to any existing grants',
        () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(
          buildTestStaffMember(id: 'target-1', organizationAccess: {'org-1'}));
      final useCase = GrantStaffOrganizationAccess(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final updated = await useCase(
        staffMemberId: 'target-1',
        organizationId: 'org-2',
        performedByStaffId: 'tenant-owner-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(updated.organizationAccess, {'org-1', 'org-2'});
    });

    test('an unknown staff member id throws', () async {
      final useCase = GrantStaffOrganizationAccess(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: InMemoryStaffMemberRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          staffMemberId: 'missing',
          organizationId: 'org-1',
          performedByStaffId: 'tenant-owner-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownAdminEntityViolation>()),
      );
    });
  });

  group('RevokeStaffOrganizationAccess', () {
    test('removes a granted organization', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(
          id: 'target-1', organizationAccess: {'org-1', 'org-2'}));
      final useCase = RevokeStaffOrganizationAccess(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final updated = await useCase(
        staffMemberId: 'target-1',
        organizationId: 'org-1',
        performedByStaffId: 'tenant-owner-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(updated.organizationAccess, {'org-2'});
    });

    test('revoking an ungranted organization is a no-op, no event', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(
          buildTestStaffMember(id: 'target-1', organizationAccess: {'org-1'}));
      final auditRepository = InMemoryAdminAuditEntryRepository();
      final useCase = RevokeStaffOrganizationAccess(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final result = await useCase(
        staffMemberId: 'target-1',
        organizationId: 'org-9',
        performedByStaffId: 'tenant-owner-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(result.organizationAccess, {'org-1'});
      expect(await auditRepository.findByTargetEntityId('target-1'), isEmpty);
    });
  });
}
