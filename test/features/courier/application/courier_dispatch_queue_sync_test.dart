import 'package:abakus_one_v2/features/courier/application/identity/courier_dispatch_queue_event_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_dispatch_queue.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/complete_delivery.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/respond_to_delivery_assignment.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/set_courier_availability.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/sync_courier_dispatch_queue.dart';
import 'package:abakus_one_v2/features/courier/data/courier_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_dispatch_queue_event_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_shift_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_assignment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_proof_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_proof_id_generator.dart';
import 'package:abakus_one_v2/features/courier/domain/availability/courier_availability_status.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_assignment.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_assignment_status.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_proof_type.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

void main() {
  group('FIFO dispatch queue sync — SetCourierAvailability', () {
    test('reaching available enters the queue', () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository.save(buildTestActiveShift());
      final queueRepository = InMemoryCourierDispatchQueueEventRepository();
      final sync = SyncCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 9, 50)),
        idGenerator: SequentialCourierDispatchQueueEventIdGenerator(),
        repository: queueRepository,
      );
      final useCase = SetCourierAvailability(
        clock: FakeClock(DateTime(2026, 1, 1, 9, 50)),
        shiftRepository: shiftRepository,
        availabilityRepository: InMemoryCourierAvailabilityRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
        dispatchQueueSync: sync,
      );

      await useCase(
        courierId: 'courier-1',
        to: CourierAvailabilityStatus.available,
        capacity: 3,
        performedByStaffId: 'courier-1',
      );

      final queue = await BuildCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 9, 50)),
        repository: queueRepository,
      )(branchId: 'branch-1');
      expect(queue.positions.single.courierId, 'courier-1');
    });

    test('reaching paused leaves the queue', () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository.save(buildTestActiveShift());
      final queueRepository = InMemoryCourierDispatchQueueEventRepository();
      final sync = SyncCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 9, 50)),
        idGenerator: SequentialCourierDispatchQueueEventIdGenerator(),
        repository: queueRepository,
      );
      final useCase = SetCourierAvailability(
        clock: FakeClock(DateTime(2026, 1, 1, 9, 50)),
        shiftRepository: shiftRepository,
        availabilityRepository: InMemoryCourierAvailabilityRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
        dispatchQueueSync: sync,
      );

      await useCase(
        courierId: 'courier-1',
        to: CourierAvailabilityStatus.available,
        capacity: 3,
        performedByStaffId: 'courier-1',
      );
      await useCase(
        courierId: 'courier-1',
        to: CourierAvailabilityStatus.paused,
        capacity: 3,
        performedByStaffId: 'courier-1',
      );

      final queue = await BuildCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 9, 50)),
        repository: queueRepository,
      )(branchId: 'branch-1');
      expect(queue.positions, isEmpty);
    });

    test('a null dispatchQueueSync never touches the queue', () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository.save(buildTestActiveShift());
      final useCase = SetCourierAvailability(
        clock: FakeClock(DateTime(2026, 1, 1, 9, 50)),
        shiftRepository: shiftRepository,
        availabilityRepository: InMemoryCourierAvailabilityRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );

      final result = await useCase(
        courierId: 'courier-1',
        to: CourierAvailabilityStatus.available,
        capacity: 3,
        performedByStaffId: 'courier-1',
      );
      expect(result.status, CourierAvailabilityStatus.available);
    });
  });

  group('FIFO dispatch queue sync — RespondToDeliveryAssignment', () {
    test('accepting an assignment leaves the queue', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
        status: DeliveryStatus.assigned,
        courierId: 'courier-1',
        currentAssignmentId: 'assignment-1',
      ));
      final assignmentRepository = InMemoryDeliveryAssignmentRepository();
      await assignmentRepository.save(DeliveryAssignment(
        id: 'assignment-1',
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        status: DeliveryAssignmentStatus.offered,
        offeredAt: DateTime(2026, 1, 1, 9, 55),
        revision: 1,
      ));
      final queueRepository = InMemoryCourierDispatchQueueEventRepository();
      final idGenerator = SequentialCourierDispatchQueueEventIdGenerator();
      final sync = SyncCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 10)),
        idGenerator: idGenerator,
        repository: queueRepository,
      );

      // Seed the courier as already in queue.
      await SyncCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 9)),
        idGenerator: idGenerator,
        repository: queueRepository,
      ).enter(courierId: 'courier-1', branchId: 'branch-1');

      final useCase = RespondToDeliveryAssignment(
        clock: FakeClock(DateTime(2026, 1, 1, 10)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentRepository: assignmentRepository,
        deliveryRepository: deliveryRepository,
        availabilityRepository: InMemoryCourierAvailabilityRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
        dispatchQueueSync: sync,
      );

      await useCase(
        assignmentId: 'assignment-1',
        courierId: 'courier-1',
        accept: true,
        performedByStaffId: 'courier-1',
      );

      final queue = await BuildCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 10)),
        repository: queueRepository,
      )(branchId: 'branch-1');
      expect(queue.positions, isEmpty);
    });
  });

  group('FIFO dispatch queue sync — CompleteDelivery', () {
    test('completing the last active delivery re-enters the queue', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
        status: DeliveryStatus.arrivedAtCustomer,
        courierId: 'courier-1',
        revision: 1,
      ));
      final queueRepository = InMemoryCourierDispatchQueueEventRepository();
      final sync = SyncCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialCourierDispatchQueueEventIdGenerator(),
        repository: queueRepository,
      );
      final useCase = CompleteDelivery(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: deliveryRepository,
        proofIdGenerator: SequentialDeliveryProofIdGenerator(),
        proofRepository: InMemoryDeliveryProofRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
        dispatchQueueSync: sync,
      );

      await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        expectedRevision: 1,
        performedByStaffId: 'courier-1',
        proofType: DeliveryProofType.courierConfirmation,
      );

      final queue = await BuildCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        repository: queueRepository,
      )(branchId: 'branch-1');
      expect(queue.positions.single.courierId, 'courier-1');
    });

    test(
        'completing a delivery while another is still active does not '
        're-enter the queue', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
        id: 'delivery-1',
        status: DeliveryStatus.arrivedAtCustomer,
        courierId: 'courier-1',
        revision: 1,
      ));
      await deliveryRepository.save(buildTestDelivery(
        id: 'delivery-2',
        status: DeliveryStatus.enRoute,
        courierId: 'courier-1',
        revision: 1,
      ));
      final queueRepository = InMemoryCourierDispatchQueueEventRepository();
      final sync = SyncCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialCourierDispatchQueueEventIdGenerator(),
        repository: queueRepository,
      );
      final useCase = CompleteDelivery(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: deliveryRepository,
        proofIdGenerator: SequentialDeliveryProofIdGenerator(),
        proofRepository: InMemoryDeliveryProofRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
        dispatchQueueSync: sync,
      );

      await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        expectedRevision: 1,
        performedByStaffId: 'courier-1',
        proofType: DeliveryProofType.courierConfirmation,
      );

      final queue = await BuildCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        repository: queueRepository,
      )(branchId: 'branch-1');
      expect(queue.positions, isEmpty);
    });
  });
}
