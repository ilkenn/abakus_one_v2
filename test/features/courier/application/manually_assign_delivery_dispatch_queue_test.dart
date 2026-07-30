import 'package:abakus_one_v2/features/courier/application/identity/courier_dispatch_queue_event_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_assignment_attempt_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_assignment_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/manually_assign_delivery.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/sync_courier_dispatch_queue.dart';
import 'package:abakus_one_v2/features/courier/data/courier_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_dispatch_queue_event_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_assignment_attempt_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_assignment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

void main() {
  group('ManuallyAssignDelivery — Sprint 5C dispatch queue override', () {
    test(
        'removes the courier from the queue and records an old/new '
        'queue audit entry when both queue collaborators are supplied',
        () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery());

      final queueRepository = InMemoryCourierDispatchQueueEventRepository();
      final idGenerator = SequentialCourierDispatchQueueEventIdGenerator();
      final sync = SyncCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 10)),
        idGenerator: idGenerator,
        repository: queueRepository,
      );
      // Seed a two-courier queue: courier-1 (target) and courier-2.
      await SyncCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 9, 50)),
        idGenerator: idGenerator,
        repository: queueRepository,
      ).enter(courierId: 'courier-1', branchId: 'branch-1');
      await SyncCourierDispatchQueue(
        clock: FakeClock(DateTime(2026, 1, 1, 9, 55)),
        idGenerator: idGenerator,
        repository: queueRepository,
      ).enter(courierId: 'courier-2', branchId: 'branch-1');

      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      final useCase = ManuallyAssignDelivery(
        clock: FakeClock(DateTime(2026, 1, 1, 10)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentIdGenerator: SequentialDeliveryAssignmentIdGenerator(),
        attemptIdGenerator: SequentialDeliveryAssignmentAttemptIdGenerator(),
        deliveryRepository: deliveryRepository,
        assignmentRepository: InMemoryDeliveryAssignmentRepository(),
        attemptRepository: InMemoryDeliveryAssignmentAttemptRepository(),
        availabilityRepository: InMemoryCourierAvailabilityRepository(),
        auditRepository: auditRepository,
        recordCourierEvent: buildTestRecordCourierEvent(),
        dispatchQueueSync: sync,
        dispatchQueueRepository: queueRepository,
      );

      await useCase(
        deliveryId: 'delivery-1',
        expectedRevision: 1,
        courierId: 'courier-1',
        overrideReason: 'Manager sıraya rağmen manuel atadı',
        overriddenByStaffId: 'manager-1',
      );

      final entries = await auditRepository.findByCourierId('courier-1');
      final overrideEntry = entries.singleWhere(
          (e) => e.type == CourierAuditEventType.dispatchQueueManualOverride);
      expect(
          overrideEntry.description, contains('before [courier-1, courier-2]'));
      expect(overrideEntry.description, contains('after [courier-2]'));
      expect(overrideEntry.reason, 'Manager sıraya rağmen manuel atadı');
      expect(overrideEntry.actorStaffId, 'manager-1');
    });

    test(
        'with no dispatch-queue collaborators supplied, no queue-override '
        'audit entry is produced and the existing behavior is unchanged',
        () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery());
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      final useCase = ManuallyAssignDelivery(
        clock: FakeClock(DateTime(2026, 1, 1, 10)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentIdGenerator: SequentialDeliveryAssignmentIdGenerator(),
        attemptIdGenerator: SequentialDeliveryAssignmentAttemptIdGenerator(),
        deliveryRepository: deliveryRepository,
        assignmentRepository: InMemoryDeliveryAssignmentRepository(),
        attemptRepository: InMemoryDeliveryAssignmentAttemptRepository(),
        availabilityRepository: InMemoryCourierAvailabilityRepository(),
        auditRepository: auditRepository,
        recordCourierEvent: buildTestRecordCourierEvent(),
      );

      final assignment = await useCase(
        deliveryId: 'delivery-1',
        expectedRevision: 1,
        courierId: 'courier-1',
        overrideReason: 'reason',
        overriddenByStaffId: 'manager-1',
      );

      expect(assignment.courierId, 'courier-1');
      final entries = await auditRepository.findByCourierId('courier-1');
      expect(
        entries.where(
            (e) => e.type == CourierAuditEventType.dispatchQueueManualOverride),
        isEmpty,
      );
      expect(
        entries.where((e) => e.type == CourierAuditEventType.manuallyAssigned),
        isNotEmpty,
      );
    });
  });
}
