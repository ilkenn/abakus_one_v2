import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/same_destination_group_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/group_same_destination_deliveries.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/same_destination_group_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';

void main() {
  group('GroupSameDestinationDeliveries', () {
    test('groups two or more deliveries and audits the decision', () async {
      final repository = InMemorySameDestinationGroupRepository();
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      final useCase = GroupSameDestinationDeliveries(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialSameDestinationGroupIdGenerator(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final group = await useCase(
        branchId: 'branch-1',
        courierId: 'courier-1',
        deliveryIds: ['delivery-1', 'delivery-2'],
        performedByStaffId: 'manager-1',
      );

      expect(group.deliveryIds, ['delivery-1', 'delivery-2']);
      expect(await repository.findByDeliveryId('delivery-1'), isNotNull);
      expect(await repository.findByDeliveryId('delivery-2'), isNotNull);
      final entries = await auditRepository.findByCourierId('courier-1');
      expect(
        entries.where(
            (e) => e.type == CourierAuditEventType.sameDestinationGrouped),
        isNotEmpty,
      );
    });

    test(
        'fewer than two deliveries is rejected before authorization is '
        'even checked', () async {
      final policy =
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true));
      final useCase = GroupSameDestinationDeliveries(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: policy,
        idGenerator: SequentialSameDestinationGroupIdGenerator(),
        repository: InMemorySameDestinationGroupRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );

      await expectLater(
        () => useCase(
          branchId: 'branch-1',
          courierId: 'courier-1',
          deliveryIds: ['delivery-1'],
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<SameDestinationGroupTooSmallViolation>()),
      );
      expect(policy.callCount, 0);
    });

    test('denied authorization throws and writes nothing', () async {
      final repository = InMemorySameDestinationGroupRepository();
      final useCase = GroupSameDestinationDeliveries(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: false)),
        idGenerator: SequentialSameDestinationGroupIdGenerator(),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );

      await expectLater(
        () => useCase(
          branchId: 'branch-1',
          courierId: 'courier-1',
          deliveryIds: ['delivery-1', 'delivery-2'],
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
      expect(await repository.findByDeliveryId('delivery-1'), isNull);
    });
  });
}
