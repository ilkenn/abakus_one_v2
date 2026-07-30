import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/set_temporary_package_blocking.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_package_blocking_status_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';

void main() {
  group('SetTemporaryPackageBlocking', () {
    test('blocks a courier and audits the change', () async {
      final repository = InMemoryCourierPackageBlockingStatusRepository();
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      final useCase = SetTemporaryPackageBlocking(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: auditRepository,
      );

      final status = await useCase(
        branchId: 'branch-1',
        courierId: 'courier-1',
        isBlocked: true,
        reason: 'Araç bakımda, mevcut teslimatları bitirsin',
        performedByStaffId: 'manager-1',
      );

      expect(status.isBlocked, isTrue);
      expect(
          (await repository.findByCourierId('courier-1'))?.isBlocked, isTrue);
      final entries = await auditRepository.findByCourierId('courier-1');
      expect(
        entries.where((e) =>
            e.type == CourierAuditEventType.temporaryPackageBlockingChanged),
        isNotEmpty,
      );
    });

    test('lifting a block is a new, higher revision', () async {
      final repository = InMemoryCourierPackageBlockingStatusRepository();
      final useCase = SetTemporaryPackageBlocking(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );

      final first = await useCase(
        branchId: 'branch-1',
        courierId: 'courier-1',
        isBlocked: true,
        performedByStaffId: 'manager-1',
      );
      final second = await useCase(
        branchId: 'branch-1',
        courierId: 'courier-1',
        isBlocked: false,
        performedByStaffId: 'manager-1',
      );

      expect(second.revision, first.revision + 1);
      expect(second.isBlocked, isFalse);
    });

    test('denied authorization throws and writes nothing', () async {
      final repository = InMemoryCourierPackageBlockingStatusRepository();
      final useCase = SetTemporaryPackageBlocking(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: false)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );

      await expectLater(
        () => useCase(
          branchId: 'branch-1',
          courierId: 'courier-1',
          isBlocked: true,
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
      expect(await repository.findByCourierId('courier-1'), isNull);
    });
  });
}
