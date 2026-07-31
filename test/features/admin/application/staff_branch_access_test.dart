import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/grant_staff_branch_access.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/revoke_staff_branch_access.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  group('GrantStaffBranchAccess', () {
    test('grants branch access, additive to any existing grants', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(
          buildTestStaffMember(id: 'target-1', branchAccess: {'branch-1'}));
      final useCase = GrantStaffBranchAccess(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final updated = await useCase(
        staffMemberId: 'target-1',
        branchId: 'branch-2',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(updated.branchAccess, {'branch-1', 'branch-2'});
    });

    test('an unknown staff member id throws', () async {
      final useCase = GrantStaffBranchAccess(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: InMemoryStaffMemberRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          staffMemberId: 'missing',
          branchId: 'branch-1',
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownAdminEntityViolation>()),
      );
    });
  });

  group('RevokeStaffBranchAccess', () {
    test('removes a granted branch', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(
          id: 'target-1', branchAccess: {'branch-1', 'branch-2'}));
      final useCase = RevokeStaffBranchAccess(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final updated = await useCase(
        staffMemberId: 'target-1',
        branchId: 'branch-1',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(updated.branchAccess, {'branch-2'});
    });

    test('revoking an ungranted branch is a no-op, no event', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(
          buildTestStaffMember(id: 'target-1', branchAccess: {'branch-1'}));
      final auditRepository = InMemoryAdminAuditEntryRepository();
      final useCase = RevokeStaffBranchAccess(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final result = await useCase(
        staffMemberId: 'target-1',
        branchId: 'branch-9',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(result.branchAccess, {'branch-1'});
      expect(await auditRepository.findByTargetEntityId('target-1'), isEmpty);
    });
  });
}
