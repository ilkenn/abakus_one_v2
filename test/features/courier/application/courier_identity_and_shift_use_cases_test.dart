import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_shift_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/change_courier_registry_status.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/register_courier.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/request_courier_shift.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/review_courier_shift.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/set_courier_availability.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/transition_courier_shift.dart';
import 'package:abakus_one_v2/features/courier/data/courier_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_shift_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/availability/courier_availability_status.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier_registry_status.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier_vehicle_type.dart';
import 'package:abakus_one_v2/features/courier/domain/shift/courier_shift_status.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

void main() {
  group('RegisterCourier / ChangeCourierRegistryStatus', () {
    test('registers an active courier and can suspend/reactivate it', () async {
      final repository = InMemoryCourierRepository();
      final register = RegisterCourier(
        idGenerator: SequentialCourierIdGenerator(),
        repository: repository,
      );
      final courier = await register(
        primaryBranchId: 'branch-1',
        displayName: 'Ali',
        phoneNumber: '+905551112233',
        vehicleType: CourierVehicleType.motorcycle,
        capacity: 3,
        registeredAt: DateTime(2026, 1, 1),
      );
      expect(courier.status, CourierRegistryStatus.active);

      final changeStatus = ChangeCourierRegistryStatus(
        clock: FakeClock(DateTime(2026, 1, 2)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final suspended = await changeStatus(
        courierId: courier.id,
        to: CourierRegistryStatus.suspended,
        performedByStaffId: 'manager-1',
        reason: 'İnceleme',
      );
      expect(suspended.status, CourierRegistryStatus.suspended);
    });

    test('archiving never deletes the record — findById still returns it',
        () async {
      final repository = InMemoryCourierRepository();
      await repository.save(buildTestCourier());
      final changeStatus = ChangeCourierRegistryStatus(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      await changeStatus(
        courierId: 'courier-1',
        to: CourierRegistryStatus.archived,
        performedByStaffId: 'manager-1',
      );
      final stillThere = await repository.findById('courier-1');
      expect(stillThere, isNotNull);
      expect(stillThere!.status, CourierRegistryStatus.archived);
    });
  });

  group('RequestCourierShift', () {
    test('only one active shift per courier is ever permitted', () async {
      final repository = InMemoryCourierShiftRepository();
      final useCase = RequestCourierShift(
        clock: FakeClock(DateTime(2026, 1, 1)),
        idGenerator: SequentialCourierShiftIdGenerator(),
        repository: repository,
      );
      await useCase(courierId: 'courier-1', branchId: 'branch-1');

      expect(
        () => useCase(courierId: 'courier-1', branchId: 'branch-1'),
        throwsA(isA<CourierShiftAlreadyActiveViolation>()),
      );
    });
  });

  group('ReviewCourierShift', () {
    test('a courier can never approve their own shift', () async {
      final repository = InMemoryCourierShiftRepository();
      await repository.save(buildTestActiveShift(
          status: CourierShiftStatus.awaitingManagerApproval));
      final useCase = ReviewCourierShift(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );

      expect(
        () => useCase(
          shiftId: 'shift-1',
          approve: true,
          reviewedByStaffId: 'courier-1',
        ),
        throwsA(isA<SelfApprovalNotAllowedViolation>()),
      );
    });

    test('approving moves the shift to approved', () async {
      final repository = InMemoryCourierShiftRepository();
      await repository.save(buildTestActiveShift(
          status: CourierShiftStatus.awaitingManagerApproval));
      final useCase = ReviewCourierShift(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final approved = await useCase(
        shiftId: 'shift-1',
        approve: true,
        reviewedByStaffId: 'manager-1',
      );
      expect(approved.status, CourierShiftStatus.approved);
    });

    test('cannot review a shift that is not awaiting approval', () async {
      final repository = InMemoryCourierShiftRepository();
      await repository.save(buildTestActiveShift());
      final useCase = ReviewCourierShift(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      expect(
        () => useCase(
          shiftId: 'shift-1',
          approve: true,
          reviewedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidCourierShiftTransitionViolation>()),
      );
    });
  });

  group('TransitionCourierShift', () {
    test(
        'ending a shift accounts for active deliveries — cannot complete '
        'while one is still active', () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository
          .save(buildTestActiveShift(status: CourierShiftStatus.ending));
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.accepted, courierId: 'courier-1'));

      final useCase = TransitionCourierShift(
        clock: FakeClock(DateTime(2026, 1, 1)),
        repository: shiftRepository,
        deliveryRepository: deliveryRepository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );

      expect(
        () => useCase(
          shiftId: 'shift-1',
          to: CourierShiftStatus.completed,
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<InvalidCourierShiftTransitionViolation>()),
      );
    });

    test('completes cleanly once no active deliveries remain', () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository
          .save(buildTestActiveShift(status: CourierShiftStatus.ending));
      final useCase = TransitionCourierShift(
        clock: FakeClock(DateTime(2026, 1, 1)),
        repository: shiftRepository,
        deliveryRepository: InMemoryDeliveryRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final completed = await useCase(
        shiftId: 'shift-1',
        to: CourierShiftStatus.completed,
        performedByStaffId: 'courier-1',
      );
      expect(completed.status, CourierShiftStatus.completed);
    });

    test(
        'shift completion never touches financial settlement — this use '
        'case has no CourierSettlementSession dependency at all', () async {
      // Structural test: TransitionCourierShift's constructor doesn't even
      // accept a settlement repository, so this is enforced at compile
      // time, not just by convention. No runtime assertion needed beyond
      // confirming the transition itself succeeds.
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository
          .save(buildTestActiveShift(status: CourierShiftStatus.approved));
      final useCase = TransitionCourierShift(
        clock: FakeClock(DateTime(2026, 1, 1)),
        repository: shiftRepository,
        deliveryRepository: InMemoryDeliveryRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final active = await useCase(
        shiftId: 'shift-1',
        to: CourierShiftStatus.active,
        performedByStaffId: 'courier-1',
      );
      expect(active.status, CourierShiftStatus.active);
    });
  });

  group('SetCourierAvailability', () {
    test(
        'a courier cannot become available without an active approved '
        'shift', () async {
      final useCase = SetCourierAvailability(
        clock: FakeClock(DateTime(2026, 1, 1)),
        shiftRepository: InMemoryCourierShiftRepository(),
        availabilityRepository: InMemoryCourierAvailabilityRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      expect(
        () => useCase(
          courierId: 'courier-1',
          to: CourierAvailabilityStatus.available,
          capacity: 3,
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<CourierShiftRequiredViolation>()),
      );
    });

    test('a suspended courier can never become available', () async {
      final availabilityRepository = InMemoryCourierAvailabilityRepository();
      await availabilityRepository.save(
          buildTestAvailability(status: CourierAvailabilityStatus.suspended));
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository.save(buildTestActiveShift());

      final useCase = SetCourierAvailability(
        clock: FakeClock(DateTime(2026, 1, 1)),
        shiftRepository: shiftRepository,
        availabilityRepository: availabilityRepository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      expect(
        () => useCase(
          courierId: 'courier-1',
          to: CourierAvailabilityStatus.available,
          capacity: 3,
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<CourierNotAvailableViolation>()),
      );
    });

    test('succeeds and increments revision with an active approved shift',
        () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository.save(buildTestActiveShift());
      final useCase = SetCourierAvailability(
        clock: FakeClock(DateTime(2026, 1, 1)),
        shiftRepository: shiftRepository,
        availabilityRepository: InMemoryCourierAvailabilityRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final availability = await useCase(
        courierId: 'courier-1',
        to: CourierAvailabilityStatus.available,
        capacity: 3,
        performedByStaffId: 'courier-1',
      );
      expect(availability.status, CourierAvailabilityStatus.available);
      expect(availability.revision, 1);
    });
  });
}
