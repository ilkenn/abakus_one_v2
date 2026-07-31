import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/revoke_staff_session.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/audit/admin_audit_event_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  group('RevokeStaffSession', () {
    test('sets sessionsRevokedAt on the member', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(id: 'target-1'));
      final useCase = RevokeStaffSession(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final updated = await useCase(
        staffMemberId: 'target-1',
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 5),
      );

      expect(updated.sessionsRevokedAt, DateTime(2026, 1, 5));
    });

    test('an unauthorized actor cannot revoke a session', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(id: 'target-1'));
      final useCase = RevokeStaffSession(
        authorizationPolicy: const DenyAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          staffMemberId: 'target-1',
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test('records an AdminAuditEntry', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(id: 'target-1'));
      final auditRepository = InMemoryAdminAuditEntryRepository();
      final useCase = RevokeStaffSession(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: auditRepository,
      );

      await useCase(
        staffMemberId: 'target-1',
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final entries = await auditRepository.findByTargetEntityId('target-1');
      expect(entries.single.type, AdminAuditEventType.staffSessionRevoked);
    });
  });
}
