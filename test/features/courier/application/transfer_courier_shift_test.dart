import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_assignment_attempt_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_assignment_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/reassign_delivery.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/transfer_courier_shift.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/transition_courier_shift.dart';
import 'package:abakus_one_v2/features/courier/data/courier_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_shift_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_assignment_attempt_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_assignment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_audit_event_type.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/courier/domain/shift/courier_shift_status.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

void main() {
  group('TransferCourierShift', () {
    late CourierShiftRepository shiftRepository;
    late DeliveryRepository deliveryRepository;
    late CourierOperationalAuditEntryRepository auditRepository;

    TransferCourierShift buildUseCase({required bool granted}) {
      final policy =
          FakePosAuthorizationPolicy(AuthorizationResult(granted: granted));
      final reassignDelivery = ReassignDelivery(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: policy,
        assignmentIdGenerator: SequentialDeliveryAssignmentIdGenerator(),
        attemptIdGenerator: SequentialDeliveryAssignmentAttemptIdGenerator(),
        deliveryRepository: deliveryRepository,
        assignmentRepository: InMemoryDeliveryAssignmentRepository(),
        attemptRepository: InMemoryDeliveryAssignmentAttemptRepository(),
        availabilityRepository: InMemoryCourierAvailabilityRepository(),
        auditRepository: auditRepository,
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final transitionCourierShift = TransitionCourierShift(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        repository: shiftRepository,
        deliveryRepository: deliveryRepository,
        auditRepository: auditRepository,
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      return TransferCourierShift(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: policy,
        shiftRepository: shiftRepository,
        deliveryRepository: deliveryRepository,
        reassignDelivery: reassignDelivery,
        transitionCourierShift: transitionCourierShift,
        auditRepository: auditRepository,
      );
    }

    setUp(() async {
      shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository.save(buildTestActiveShift());
      deliveryRepository = InMemoryDeliveryRepository();
      auditRepository = InMemoryCourierOperationalAuditEntryRepository();
    });

    test(
        'moves every active delivery to the new courier and suspends the '
        'source shift', () async {
      await deliveryRepository.save(buildTestDelivery(
        id: 'delivery-1',
        courierId: 'courier-1',
        status: DeliveryStatus.accepted,
      ));

      final useCase = buildUseCase(granted: true);
      final updatedShift = await useCase(
        fromShiftId: 'shift-1',
        toCourierId: 'courier-2',
        reason: 'Ahmet hastalandı',
        performedByStaffId: 'manager-1',
      );

      expect(updatedShift.status, CourierShiftStatus.suspended);
      final delivery = await deliveryRepository.findById('delivery-1');
      expect(delivery?.courierId, 'courier-2');

      final entries = await auditRepository.findByCourierId('courier-1');
      expect(
        entries.where((e) => e.type == CourierAuditEventType.shiftTransferred),
        isNotEmpty,
      );
    });

    test('an empty reason is rejected before authorization is checked',
        () async {
      final useCase = buildUseCase(granted: true);
      await expectLater(
        () => useCase(
          fromShiftId: 'shift-1',
          toCourierId: 'courier-2',
          reason: '   ',
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<ManualOverrideReasonRequiredViolation>()),
      );
    });

    test('a non-active shift cannot be transferred', () async {
      await shiftRepository.save(buildTestActiveShift(
        status: CourierShiftStatus.completed,
        revision: 2,
      ));
      final useCase = buildUseCase(granted: true);
      await expectLater(
        () => useCase(
          fromShiftId: 'shift-1',
          toCourierId: 'courier-2',
          reason: 'reason',
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidCourierShiftTransitionViolation>()),
      );
    });

    test('denied authorization throws and moves nothing', () async {
      await deliveryRepository.save(buildTestDelivery(
        id: 'delivery-1',
        courierId: 'courier-1',
        status: DeliveryStatus.accepted,
      ));
      final useCase = buildUseCase(granted: false);
      await expectLater(
        () => useCase(
          fromShiftId: 'shift-1',
          toCourierId: 'courier-2',
          reason: 'reason',
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
      final delivery = await deliveryRepository.findById('delivery-1');
      expect(delivery?.courierId, 'courier-1');
    });

    test('a shift with no active deliveries still transfers cleanly', () async {
      final useCase = buildUseCase(granted: true);
      final updatedShift = await useCase(
        fromShiftId: 'shift-1',
        toCourierId: 'courier-2',
        reason: 'reason',
        performedByStaffId: 'manager-1',
      );
      expect(updatedShift.status, CourierShiftStatus.suspended);
    });
  });
}
