import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/set_staff_member_status.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/staff/staff_member_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  group('SetStaffMemberStatus', () {
    test('suspends an active member', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(id: 'target-1'));
      final useCase = SetStaffMemberStatus(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final updated = await useCase(
        staffMemberId: 'target-1',
        newStatus: StaffMemberStatus.suspended,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(updated.status, StaffMemberStatus.suspended);
    });

    test('reinstates a suspended member back to active', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(
          id: 'target-1', status: StaffMemberStatus.suspended));
      final useCase = SetStaffMemberStatus(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final updated = await useCase(
        staffMemberId: 'target-1',
        newStatus: StaffMemberStatus.active,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(updated.status, StaffMemberStatus.active);
    });

    test('archived is terminal — cannot be changed again', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(
          id: 'target-1', status: StaffMemberStatus.archived));
      final useCase = SetStaffMemberStatus(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          staffMemberId: 'target-1',
          newStatus: StaffMemberStatus.active,
          performedByStaffId: 'admin-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<StaffMemberArchivedViolation>()),
      );
    });

    test('an unauthorized actor cannot change status', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(id: 'target-1'));
      final useCase = SetStaffMemberStatus(
        authorizationPolicy: const DenyAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          staffMemberId: 'target-1',
          newStatus: StaffMemberStatus.suspended,
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
