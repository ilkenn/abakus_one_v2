import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_assignment_attempt_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_assignment_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/cancel_delivery_assignment.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/manually_assign_delivery.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/offer_delivery_assignment.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/reassign_delivery.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/respond_to_delivery_assignment.dart';
import 'package:abakus_one_v2/features/courier/data/courier_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_assignment_attempt_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_assignment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_assignment.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_assignment_status.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/courier/domain/dispatch/dispatch_scoring_input.dart';
import 'package:abakus_one_v2/features/courier/domain/feedback/courier_feedback_tag.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

DispatchScoringInput _eligibleCandidate(String courierId) {
  return DispatchScoringInput(
    courierId: courierId,
    isAvailable: true,
    isEligibleForBranch: true,
    activeDeliveryCount: 0,
    capacity: 3,
    distanceEstimateMeters: 500,
    packageWaitSeconds: 60,
    recentRejectionCount: 0,
  );
}

OfferDeliveryAssignment _offerUseCase({
  required DeliveryRepository deliveryRepository,
  required DeliveryAssignmentRepository assignmentRepository,
}) {
  return OfferDeliveryAssignment(
    clock: FakeClock(DateTime(2026, 1, 1)),
    authorizationPolicy:
        FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
    assignmentIdGenerator: SequentialDeliveryAssignmentIdGenerator(),
    attemptIdGenerator: SequentialDeliveryAssignmentAttemptIdGenerator(),
    deliveryRepository: deliveryRepository,
    assignmentRepository: assignmentRepository,
    attemptRepository: InMemoryDeliveryAssignmentAttemptRepository(),
    auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
    recordCourierEvent: buildTestRecordCourierEvent(),
  );
}

void main() {
  group('OfferDeliveryAssignment', () {
    test('throws when no eligible candidate exists', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery());
      final useCase = _offerUseCase(
        deliveryRepository: deliveryRepository,
        assignmentRepository: InMemoryDeliveryAssignmentRepository(),
      );
      expect(
        () => useCase(
          deliveryId: 'delivery-1',
          expectedRevision: 1,
          candidates: [
            const DispatchScoringInput(
              courierId: 'courier-1',
              isAvailable: false,
              isEligibleForBranch: true,
              activeDeliveryCount: 0,
              capacity: 3,
              packageWaitSeconds: 0,
              recentRejectionCount: 0,
            ),
          ],
          performedByStaffId: 'system',
        ),
        throwsA(isA<CourierNotAvailableViolation>()),
      );
    });

    test(
        'offers to the top-ranked eligible candidate and advances the '
        'delivery to assigned', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery());
      final assignmentRepository = InMemoryDeliveryAssignmentRepository();
      final useCase = _offerUseCase(
        deliveryRepository: deliveryRepository,
        assignmentRepository: assignmentRepository,
      );
      final assignment = await useCase(
        deliveryId: 'delivery-1',
        expectedRevision: 1,
        candidates: [_eligibleCandidate('courier-1')],
        performedByStaffId: 'system',
      );
      expect(assignment.courierId, 'courier-1');
      expect(assignment.status, DeliveryAssignmentStatus.offered);
      final delivery = await deliveryRepository.findById('delivery-1');
      expect(delivery!.status, DeliveryStatus.assigned);
      expect(delivery.currentAssignmentId, assignment.id);
    });

    test(
        'one delivery cannot have two active accepted couriers — a second '
        'offer is rejected once already assigned', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
        status: DeliveryStatus.assigned,
        currentAssignmentId: 'existing-assignment',
      ));
      final useCase = _offerUseCase(
        deliveryRepository: deliveryRepository,
        assignmentRepository: InMemoryDeliveryAssignmentRepository(),
      );
      expect(
        () => useCase(
          deliveryId: 'delivery-1',
          expectedRevision: 1,
          candidates: [_eligibleCandidate('courier-2')],
          performedByStaffId: 'system',
        ),
        throwsA(isA<DeliveryAlreadyAssignedViolation>()),
      );
    });
  });

  group('RespondToDeliveryAssignment', () {
    Future<
        ({
          DeliveryRepository deliveries,
          DeliveryAssignmentRepository assignments,
          CourierAvailabilityRepository availability,
        })> setup() async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
        status: DeliveryStatus.assigned,
        courierId: 'courier-1',
        currentAssignmentId: 'assign-1',
      ));
      final assignmentRepository = InMemoryDeliveryAssignmentRepository();
      await assignmentRepository.save(DeliveryAssignment(
        id: 'assign-1',
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        status: DeliveryAssignmentStatus.offered,
        offeredAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final availabilityRepository = InMemoryCourierAvailabilityRepository();
      await availabilityRepository.save(buildTestAvailability());
      return (
        deliveries: deliveryRepository,
        assignments: assignmentRepository,
        availability: availabilityRepository,
      );
    }

    test('rejection requires a predefined reason tag', () async {
      final env = await setup();
      final useCase = RespondToDeliveryAssignment(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentRepository: env.assignments,
        deliveryRepository: env.deliveries,
        availabilityRepository: env.availability,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      expect(
        () => useCase(
          assignmentId: 'assign-1',
          courierId: 'courier-1',
          accept: false,
          rejectionReasonCode: 'not-a-real-tag',
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<InvalidAssignmentRejectionReasonViolation>()),
      );
    });

    test('accepting increments CourierAvailability.activeAssignmentCount',
        () async {
      final env = await setup();
      final useCase = RespondToDeliveryAssignment(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentRepository: env.assignments,
        deliveryRepository: env.deliveries,
        availabilityRepository: env.availability,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      await useCase(
        assignmentId: 'assign-1',
        courierId: 'courier-1',
        accept: true,
        performedByStaffId: 'courier-1',
      );
      final delivery = await env.deliveries.findById('delivery-1');
      expect(delivery!.status, DeliveryStatus.accepted);
      final availability = await env.availability.findByCourierId('courier-1');
      expect(availability!.activeAssignmentCount, 1);
    });

    test(
        'rejecting requeues the delivery to readyForAssignment while '
        'leaving the rejected assignment record untouched (full history '
        'preserved)', () async {
      final env = await setup();
      final useCase = RespondToDeliveryAssignment(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentRepository: env.assignments,
        deliveryRepository: env.deliveries,
        availabilityRepository: env.availability,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final result = await useCase(
        assignmentId: 'assign-1',
        courierId: 'courier-1',
        accept: false,
        rejectionReasonCode: CourierFeedbackTag.trafficDelay.name,
        performedByStaffId: 'courier-1',
      );
      expect(result.status, DeliveryAssignmentStatus.rejected);
      expect(result.rejectionReasonCode, CourierFeedbackTag.trafficDelay.name);

      final delivery = await env.deliveries.findById('delivery-1');
      expect(delivery!.status, DeliveryStatus.readyForAssignment);
      expect(delivery.courierId, isNull);
      expect(delivery.currentAssignmentId, isNull);
    });

    test(
        'a courier cannot respond to an assignment offered to someone '
        'else', () async {
      final env = await setup();
      final useCase = RespondToDeliveryAssignment(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentRepository: env.assignments,
        deliveryRepository: env.deliveries,
        availabilityRepository: env.availability,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      expect(
        () => useCase(
          assignmentId: 'assign-1',
          courierId: 'someone-else',
          accept: true,
          performedByStaffId: 'someone-else',
        ),
        throwsA(isA<DeliveryNotAssignedToCourierViolation>()),
      );
    });
  });

  group('ManuallyAssignDelivery', () {
    test('requires a non-empty override reason', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery());
      final useCase = ManuallyAssignDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentIdGenerator: SequentialDeliveryAssignmentIdGenerator(),
        attemptIdGenerator: SequentialDeliveryAssignmentAttemptIdGenerator(),
        deliveryRepository: deliveryRepository,
        assignmentRepository: InMemoryDeliveryAssignmentRepository(),
        attemptRepository: InMemoryDeliveryAssignmentAttemptRepository(),
        availabilityRepository: InMemoryCourierAvailabilityRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      expect(
        () => useCase(
          deliveryId: 'delivery-1',
          expectedRevision: 1,
          courierId: 'courier-1',
          overrideReason: '   ',
          overriddenByStaffId: 'manager-1',
        ),
        throwsA(isA<ManualOverrideReasonRequiredViolation>()),
      );
    });

    test('bypasses scoring and lands directly at accepted', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery());
      final assignmentRepository = InMemoryDeliveryAssignmentRepository();
      final useCase = ManuallyAssignDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentIdGenerator: SequentialDeliveryAssignmentIdGenerator(),
        attemptIdGenerator: SequentialDeliveryAssignmentAttemptIdGenerator(),
        deliveryRepository: deliveryRepository,
        assignmentRepository: assignmentRepository,
        attemptRepository: InMemoryDeliveryAssignmentAttemptRepository(),
        availabilityRepository: InMemoryCourierAvailabilityRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final assignment = await useCase(
        deliveryId: 'delivery-1',
        expectedRevision: 1,
        courierId: 'courier-9',
        overrideReason: 'Acil sipariş',
        overriddenByStaffId: 'manager-1',
      );
      expect(assignment.status, DeliveryAssignmentStatus.accepted);
      expect(assignment.isManualOverride, isTrue);
      expect(assignment.overrideReason, 'Acil sipariş');
      final delivery = await deliveryRepository.findById('delivery-1');
      expect(delivery!.status, DeliveryStatus.accepted);
      expect(delivery.courierId, 'courier-9');
    });
  });

  group('ReassignDelivery', () {
    test(
        'preserves the superseded assignment untouched and creates a new '
        'one for the replacement courier', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
        status: DeliveryStatus.accepted,
        courierId: 'courier-1',
        currentAssignmentId: 'old-assign',
      ));
      final assignmentRepository = InMemoryDeliveryAssignmentRepository();
      await assignmentRepository.save(DeliveryAssignment(
        id: 'old-assign',
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        status: DeliveryAssignmentStatus.accepted,
        offeredAt: DateTime(2026, 1, 1),
        respondedAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final useCase = ReassignDelivery(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentIdGenerator: SequentialDeliveryAssignmentIdGenerator(),
        attemptIdGenerator: SequentialDeliveryAssignmentAttemptIdGenerator(),
        deliveryRepository: deliveryRepository,
        assignmentRepository: assignmentRepository,
        attemptRepository: InMemoryDeliveryAssignmentAttemptRepository(),
        availabilityRepository: InMemoryCourierAvailabilityRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final newAssignment = await useCase(
        deliveryId: 'delivery-1',
        expectedRevision: 1,
        newCourierId: 'courier-2',
        overrideReason: 'Kurye arıza yaptı',
        performedByStaffId: 'manager-1',
      );
      expect(newAssignment.courierId, 'courier-2');
      expect(newAssignment.status, DeliveryAssignmentStatus.accepted);

      // The old assignment record is untouched — still shows the true
      // historical fact that courier-1 had accepted it.
      final oldAssignment = await assignmentRepository.findById('old-assign');
      expect(oldAssignment!.courierId, 'courier-1');
      expect(oldAssignment.status, DeliveryAssignmentStatus.accepted);

      final delivery = await deliveryRepository.findById('delivery-1');
      expect(delivery!.courierId, 'courier-2');
      expect(delivery.status, DeliveryStatus.accepted);
    });
  });

  group('CancelDeliveryAssignment', () {
    test('only a still-offered assignment can be cancelled', () async {
      final assignmentRepository = InMemoryDeliveryAssignmentRepository();
      await assignmentRepository.save(DeliveryAssignment(
        id: 'assign-1',
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        status: DeliveryAssignmentStatus.accepted,
        offeredAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.accepted, currentAssignmentId: 'assign-1'));
      final useCase = CancelDeliveryAssignment(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentRepository: assignmentRepository,
        deliveryRepository: deliveryRepository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      expect(
        () => useCase(
          assignmentId: 'assign-1',
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidDeliveryAssignmentTransitionViolation>()),
      );
    });

    test('cancelling an offered assignment requeues the delivery', () async {
      final assignmentRepository = InMemoryDeliveryAssignmentRepository();
      await assignmentRepository.save(DeliveryAssignment(
        id: 'assign-1',
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        status: DeliveryAssignmentStatus.offered,
        offeredAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.assigned, currentAssignmentId: 'assign-1'));
      final useCase = CancelDeliveryAssignment(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentRepository: assignmentRepository,
        deliveryRepository: deliveryRepository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final result = await useCase(
        assignmentId: 'assign-1',
        performedByStaffId: 'manager-1',
        reason: 'Kurye ulaşılamıyor',
      );
      expect(result.status, DeliveryAssignmentStatus.cancelled);
      final delivery = await deliveryRepository.findById('delivery-1');
      expect(delivery!.status, DeliveryStatus.readyForAssignment);
    });

    test('isExpiry=true records an expired status instead of cancelled',
        () async {
      final assignmentRepository = InMemoryDeliveryAssignmentRepository();
      await assignmentRepository.save(DeliveryAssignment(
        id: 'assign-1',
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        status: DeliveryAssignmentStatus.offered,
        offeredAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.assigned, currentAssignmentId: 'assign-1'));
      final useCase = CancelDeliveryAssignment(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        assignmentRepository: assignmentRepository,
        deliveryRepository: deliveryRepository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final result = await useCase(
        assignmentId: 'assign-1',
        isExpiry: true,
        performedByStaffId: 'system',
      );
      expect(result.status, DeliveryAssignmentStatus.expired);
    });
  });
}
