import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/reorder_courier_delivery_sequence.dart';
import 'package:abakus_one_v2/features/courier/data/courier_delivery_sequence_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_audit_event_type.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

void main() {
  group('ReorderCourierDeliverySequence', () {
    late DeliveryRepository deliveryRepository;
    late CourierDeliverySequenceRepository sequenceRepository;
    late CourierOperationalAuditEntryRepository auditRepository;

    setUp(() async {
      deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
        id: 'delivery-1',
        courierId: 'courier-1',
        status: DeliveryStatus.accepted,
      ));
      await deliveryRepository.save(buildTestDelivery(
        id: 'delivery-2',
        courierId: 'courier-1',
        status: DeliveryStatus.arrivedAtRestaurant,
      ));
      sequenceRepository = InMemoryCourierDeliverySequenceRepository();
      auditRepository = InMemoryCourierOperationalAuditEntryRepository();
    });

    ReorderCourierDeliverySequence buildUseCase({required bool granted}) {
      return ReorderCourierDeliverySequence(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy:
            FakePosAuthorizationPolicy(AuthorizationResult(granted: granted)),
        deliveryRepository: deliveryRepository,
        sequenceRepository: sequenceRepository,
        auditRepository: auditRepository,
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
    }

    test(
        'a valid reorder (same set, different order) is accepted and '
        'audited', () async {
      final useCase = buildUseCase(granted: true);
      final result = await useCase(
        courierId: 'courier-1',
        branchId: 'branch-1',
        newOrder: ['delivery-2', 'delivery-1'],
        performedByStaffId: 'manager-1',
        reason: 'Delivery-2 daha yakın',
      );

      expect(result.orderedDeliveryIds, ['delivery-2', 'delivery-1']);
      final entries = await auditRepository.findByCourierId('courier-1');
      final entry = entries.singleWhere(
          (e) => e.type == CourierAuditEventType.deliverySequenceReordered);
      expect(entry.reason, 'Delivery-2 daha yakın');
      expect(entry.actorStaffId, 'manager-1');
    });

    test(
        'a submitted order missing one of the courier\'s active '
        'deliveries is rejected', () async {
      final useCase = buildUseCase(granted: true);
      expect(
        () => useCase(
          courierId: 'courier-1',
          branchId: 'branch-1',
          newOrder: ['delivery-1'],
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidDeliverySequenceViolation>()),
      );
    });

    test('a submitted order including an unknown delivery id is rejected',
        () async {
      final useCase = buildUseCase(granted: true);
      expect(
        () => useCase(
          courierId: 'courier-1',
          branchId: 'branch-1',
          newOrder: ['delivery-1', 'delivery-2', 'delivery-999'],
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidDeliverySequenceViolation>()),
      );
    });

    test('a duplicated delivery id in the submitted order is rejected',
        () async {
      final useCase = buildUseCase(granted: true);
      expect(
        () => useCase(
          courierId: 'courier-1',
          branchId: 'branch-1',
          newOrder: ['delivery-1', 'delivery-1'],
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidDeliverySequenceViolation>()),
      );
    });

    test('denied authorization throws and writes nothing', () async {
      final useCase = buildUseCase(granted: false);
      await expectLater(
        () => useCase(
          courierId: 'courier-1',
          branchId: 'branch-1',
          newOrder: ['delivery-1', 'delivery-2'],
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
      expect(
          await sequenceRepository.findLatestByCourierId('courier-1'), isNull);
    });

    test(
        'a completed delivery can never appear in a valid submission, '
        'since it is excluded from the courier\'s active set', () async {
      await deliveryRepository.save(buildTestDelivery(
        id: 'delivery-3',
        courierId: 'courier-1',
        status: DeliveryStatus.delivered,
      ));
      final useCase = buildUseCase(granted: true);
      expect(
        () => useCase(
          courierId: 'courier-1',
          branchId: 'branch-1',
          newOrder: ['delivery-1', 'delivery-2', 'delivery-3'],
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidDeliverySequenceViolation>()),
      );
    });

    test(
        'each reorder is a new, higher revision — never an edit of the '
        'previous one', () async {
      final useCase = buildUseCase(granted: true);
      final first = await useCase(
        courierId: 'courier-1',
        branchId: 'branch-1',
        newOrder: ['delivery-1', 'delivery-2'],
        performedByStaffId: 'manager-1',
      );
      final second = await useCase(
        courierId: 'courier-1',
        branchId: 'branch-1',
        newOrder: ['delivery-2', 'delivery-1'],
        performedByStaffId: 'manager-1',
      );
      expect(second.revision, first.revision + 1);
    });
  });
}
