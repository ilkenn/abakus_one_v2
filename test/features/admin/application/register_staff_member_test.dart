import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/register_staff_member.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/audit/admin_audit_event_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  group('RegisterStaffMember', () {
    test('creates a new staff member with no roles', () async {
      final repository = InMemoryStaffMemberRepository();
      final useCase = RegisterStaffMember(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final member = await useCase(
        displayName: 'Ayşe Yılmaz',
        email: 'ayse@example.test',
        performedByStaffId: 'admin-1',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(member.displayName, 'Ayşe Yılmaz');
      expect(member.roles, isEmpty);
      expect(await repository.findById(member.id), member);
    });

    test('an unauthorized actor cannot register a staff member', () async {
      final useCase = RegisterStaffMember(
        authorizationPolicy: const DenyAllAdminPolicy(),
        repository: InMemoryStaffMemberRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          displayName: 'Ayşe Yılmaz',
          email: 'ayse@example.test',
          performedByStaffId: 'staff-1',
          createdAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test('records an AdminAuditEntry', () async {
      final auditRepository = InMemoryAdminAuditEntryRepository();
      final useCase = RegisterStaffMember(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: InMemoryStaffMemberRepository(),
        auditRepository: auditRepository,
      );

      final member = await useCase(
        displayName: 'Ayşe Yılmaz',
        email: 'ayse@example.test',
        performedByStaffId: 'admin-1',
        createdAt: DateTime(2026, 1, 1),
      );

      final entries = await auditRepository.findByTargetEntityId(member.id);
      expect(entries.single.type, AdminAuditEventType.staffMemberRegistered);
      expect(entries.single.actorId, 'admin-1');
    });
  });
}
