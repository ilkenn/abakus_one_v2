import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/set_maintenance_mode.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/maintenance_mode_state_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  group('SetMaintenanceMode', () {
    test('activates maintenance mode with a reason', () async {
      final repository = InMemoryMaintenanceModeStateRepository();
      final useCase = SetMaintenanceMode(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final state = await useCase(
        isActive: true,
        reason: 'Planned upgrade',
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(state.isActive, isTrue);
      expect(state.reason, 'Planned upgrade');
      expect((await repository.find())!.isActive, isTrue);
    });

    test('deactivating clears the reason', () async {
      final repository = InMemoryMaintenanceModeStateRepository();
      final useCase = SetMaintenanceMode(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );
      await useCase(
        isActive: true,
        reason: 'Planned upgrade',
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final state = await useCase(
        isActive: false,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(state.isActive, isFalse);
      expect(state.reason, isNull);
    });

    test('an unauthorized actor cannot change maintenance mode', () async {
      final useCase = SetMaintenanceMode(
        authorizationPolicy: const DenyAllAdminPolicy(),
        repository: InMemoryMaintenanceModeStateRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          isActive: true,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
