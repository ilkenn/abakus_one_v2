import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_proof_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/complete_delivery.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/confirm_package_pickup.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/create_delivery.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/mark_delivery_ready_for_assignment.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/transition_delivery.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_proof_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_proof_type.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/courier/domain/location/geofence_evaluation_result.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

void main() {
  group('CreateDelivery', () {
    test('creates at created then immediately advances to awaitingPackage',
        () async {
      final repository = InMemoryDeliveryRepository();
      final useCase = CreateDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        idGenerator: SequentialDeliveryIdGenerator(),
        repository: repository,
      );
      final delivery =
          await useCase(orderId: OrderId('order-1'), branchId: 'branch-1');
      expect(delivery.status, DeliveryStatus.awaitingPackage);
      expect(delivery.revision, 2);
    });

    test(
        'is idempotent — a second call for the same orderId returns the '
        'existing Delivery instead of creating a duplicate', () async {
      final repository = InMemoryDeliveryRepository();
      final useCase = CreateDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        idGenerator: SequentialDeliveryIdGenerator(),
        repository: repository,
      );
      final first =
          await useCase(orderId: OrderId('order-1'), branchId: 'branch-1');
      final second =
          await useCase(orderId: OrderId('order-1'), branchId: 'branch-1');
      expect(second.id, first.id);
      expect(
        (await repository.findActiveByBranchId('branch-1')).length,
        1,
      );
    });
  });

  group('MarkDeliveryReadyForAssignment', () {
    test('moves awaitingPackage to readyForAssignment', () async {
      final repository = InMemoryDeliveryRepository();
      await repository
          .save(buildTestDelivery(status: DeliveryStatus.awaitingPackage));
      final useCase = MarkDeliveryReadyForAssignment(repository: repository);
      final updated = await useCase(deliveryId: 'delivery-1');
      expect(updated.status, DeliveryStatus.readyForAssignment);
    });

    test('rejects skipping straight from created', () async {
      final repository = InMemoryDeliveryRepository();
      await repository.save(buildTestDelivery(status: DeliveryStatus.created));
      final useCase = MarkDeliveryReadyForAssignment(repository: repository);
      expect(
        () => useCase(deliveryId: 'delivery-1'),
        throwsA(isA<InvalidDeliveryTransitionViolation>()),
      );
    });
  });

  group('TransitionDelivery', () {
    test(
        'a geofence failure without an override blocks restaurant '
        'arrival', () async {
      final repository = InMemoryDeliveryRepository();
      await repository.save(
          buildTestDelivery(status: DeliveryStatus.accepted, revision: 1));
      final useCase = TransitionDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      const failingResult = GeofenceEvaluationResult(
        isWithin: false,
        distanceMeters: 500,
        isAccuracySufficient: true,
      );
      expect(
        () => useCase(
          deliveryId: 'delivery-1',
          to: DeliveryStatus.arrivedAtRestaurant,
          expectedRevision: 1,
          performedByStaffId: 'courier-1',
          geofenceResult: failingResult,
        ),
        throwsA(isA<GeofenceRequiresOverrideViolation>()),
      );
    });

    test('an override id bypasses a failing geofence check', () async {
      final repository = InMemoryDeliveryRepository();
      await repository.save(
          buildTestDelivery(status: DeliveryStatus.accepted, revision: 1));
      final useCase = TransitionDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      const failingResult = GeofenceEvaluationResult(
        isWithin: false,
        distanceMeters: 500,
        isAccuracySufficient: true,
      );
      final updated = await useCase(
        deliveryId: 'delivery-1',
        to: DeliveryStatus.arrivedAtRestaurant,
        expectedRevision: 1,
        performedByStaffId: 'courier-1',
        geofenceResult: failingResult,
        geofenceOverrideId: 'override-1',
      );
      expect(updated.status, DeliveryStatus.arrivedAtRestaurant);
    });

    test('rejects an invalid transition', () async {
      final repository = InMemoryDeliveryRepository();
      await repository.save(buildTestDelivery(
          status: DeliveryStatus.readyForAssignment, revision: 1));
      final useCase = TransitionDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      expect(
        () => useCase(
          deliveryId: 'delivery-1',
          to: DeliveryStatus.delivered,
          expectedRevision: 1,
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<InvalidDeliveryTransitionViolation>()),
      );
    });
  });

  group('ConfirmPackagePickup', () {
    test('courier cannot pick up an unprepared package', () async {
      final repository = InMemoryDeliveryRepository();
      await repository
          .save(buildTestDelivery(status: DeliveryStatus.arrivedAtRestaurant));
      final useCase = ConfirmPackagePickup(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
        isPackageReadyForPickup: ({required orderId}) async => false,
        advanceToCourierCollected: (
                {required orderId,
                required performedByStaffId,
                required at}) async =>
            fail('should not be called when package is not ready'),
      );
      expect(
        () =>
            useCase(deliveryId: 'delivery-1', performedByStaffId: 'courier-1'),
        throwsA(isA<PackageNotReadyForPickupViolation>()),
      );
    });

    test(
        'is idempotent — a second call on an already-pickedUp delivery '
        'returns unchanged without re-advancing PackagePreparation', () async {
      final repository = InMemoryDeliveryRepository();
      await repository.save(buildTestDelivery(status: DeliveryStatus.pickedUp));
      var advanceCallCount = 0;
      final useCase = ConfirmPackagePickup(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
        isPackageReadyForPickup: ({required orderId}) async => true,
        advanceToCourierCollected: (
            {required orderId,
            required performedByStaffId,
            required at}) async {
          advanceCallCount++;
        },
      );
      final result = await useCase(
          deliveryId: 'delivery-1', performedByStaffId: 'courier-1');
      expect(result.status, DeliveryStatus.pickedUp);
      expect(advanceCallCount, 0);
    });

    test('a ready package is picked up and advances PackagePreparation',
        () async {
      final repository = InMemoryDeliveryRepository();
      await repository
          .save(buildTestDelivery(status: DeliveryStatus.arrivedAtRestaurant));
      var advanceCallCount = 0;
      final useCase = ConfirmPackagePickup(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
        isPackageReadyForPickup: ({required orderId}) async => true,
        advanceToCourierCollected: (
            {required orderId,
            required performedByStaffId,
            required at}) async {
          advanceCallCount++;
        },
      );
      final result = await useCase(
          deliveryId: 'delivery-1', performedByStaffId: 'courier-1');
      expect(result.status, DeliveryStatus.pickedUp);
      expect(advanceCallCount, 1);
    });
  });

  group('CompleteDelivery', () {
    test('a courier cannot complete a delivery not assigned to them', () async {
      final repository = InMemoryDeliveryRepository();
      await repository.save(buildTestDelivery(
          status: DeliveryStatus.arrivedAtCustomer, courierId: 'courier-1'));
      final useCase = CompleteDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        proofIdGenerator: SequentialDeliveryProofIdGenerator(),
        proofRepository: InMemoryDeliveryProofRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      expect(
        () => useCase(
          deliveryId: 'delivery-1',
          courierId: 'courier-2',
          expectedRevision: 1,
          performedByStaffId: 'courier-2',
          proofType: DeliveryProofType.courierConfirmation,
        ),
        throwsA(isA<DeliveryNotAssignedToCourierViolation>()),
      );
    });

    test('a stale expectedRevision is rejected', () async {
      final repository = InMemoryDeliveryRepository();
      await repository.save(buildTestDelivery(
          status: DeliveryStatus.arrivedAtCustomer,
          courierId: 'courier-1',
          revision: 3));
      final useCase = CompleteDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        proofIdGenerator: SequentialDeliveryProofIdGenerator(),
        proofRepository: InMemoryDeliveryProofRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      expect(
        () => useCase(
          deliveryId: 'delivery-1',
          courierId: 'courier-1',
          expectedRevision: 1,
          performedByStaffId: 'courier-1',
          proofType: DeliveryProofType.courierConfirmation,
        ),
        throwsA(isA<StaleCourierRevisionViolation>()),
      );
    });

    test(
        'is idempotent — a second call on a delivered delivery returns it '
        'unchanged rather than erroring', () async {
      final repository = InMemoryDeliveryRepository();
      await repository.save(buildTestDelivery(
          status: DeliveryStatus.delivered,
          courierId: 'courier-1',
          revision: 5));
      final useCase = CompleteDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        proofIdGenerator: SequentialDeliveryProofIdGenerator(),
        proofRepository: InMemoryDeliveryProofRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final result = await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        expectedRevision: 999, // deliberately wrong — must not matter
        performedByStaffId: 'courier-1',
        proofType: DeliveryProofType.courierConfirmation,
      );
      expect(result.status, DeliveryStatus.delivered);
      expect(result.revision, 5);
    });

    test(
        'completion never touches PaymentSession/CourierCashCollection — '
        'the advanceToDelivered closure is only called for the '
        'PackagePreparation bridge, cash collection is a fully separate '
        'action', () async {
      final repository = InMemoryDeliveryRepository();
      await repository.save(buildTestDelivery(
          status: DeliveryStatus.arrivedAtCustomer,
          courierId: 'courier-1',
          revision: 1));
      String? advancedOrderId;
      final useCase = CompleteDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        proofIdGenerator: SequentialDeliveryProofIdGenerator(),
        proofRepository: InMemoryDeliveryProofRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
        advanceToDelivered: ({
          required OrderId orderId,
          required String performedByStaffId,
          required DateTime at,
        }) async {
          advancedOrderId = orderId.value;
        },
      );
      final result = await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        expectedRevision: 1,
        performedByStaffId: 'courier-1',
        proofType: DeliveryProofType.courierConfirmation,
      );
      expect(result.status, DeliveryStatus.delivered);
      expect(advancedOrderId, 'order-1');
    });

    test('recordVisitAndEvaluateRewards fires on a fresh completion', () async {
      final repository = InMemoryDeliveryRepository();
      await repository.save(buildTestDelivery(
          status: DeliveryStatus.arrivedAtCustomer,
          courierId: 'courier-1',
          revision: 1));
      String? recordedOrderId;
      final useCase = CompleteDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        proofIdGenerator: SequentialDeliveryProofIdGenerator(),
        proofRepository: InMemoryDeliveryProofRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
        recordVisitAndEvaluateRewards: ({
          required OrderId orderId,
          required String branchId,
          required DateTime at,
        }) async {
          recordedOrderId = orderId.value;
        },
      );
      await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        expectedRevision: 1,
        performedByStaffId: 'courier-1',
        proofType: DeliveryProofType.courierConfirmation,
      );
      expect(recordedOrderId, 'order-1');
    });

    test(
        'recordVisitAndEvaluateRewards never fires on the idempotent '
        'already-delivered path — "duplicate completion event" must not '
        'trigger a second visit evaluation', () async {
      final repository = InMemoryDeliveryRepository();
      await repository.save(buildTestDelivery(
          status: DeliveryStatus.delivered,
          courierId: 'courier-1',
          revision: 5));
      var recordVisitCallCount = 0;
      final useCase = CompleteDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        proofIdGenerator: SequentialDeliveryProofIdGenerator(),
        proofRepository: InMemoryDeliveryProofRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
        recordVisitAndEvaluateRewards: ({
          required OrderId orderId,
          required String branchId,
          required DateTime at,
        }) async {
          recordVisitCallCount++;
        },
      );
      await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        expectedRevision: 999,
        performedByStaffId: 'courier-1',
        proofType: DeliveryProofType.courierConfirmation,
      );
      expect(recordVisitCallCount, 0);
    });
  });
}
