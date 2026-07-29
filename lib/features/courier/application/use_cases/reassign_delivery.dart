import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_availability_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/delivery_assignment_attempt_repository.dart';
import '../../data/delivery_assignment_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/delivery/delivery_assignment.dart';
import '../../domain/delivery/delivery_assignment_attempt.dart';
import '../../domain/delivery/delivery_assignment_status.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/events/courier_event_type.dart';
import '../identity/delivery_assignment_attempt_id_generator.dart';
import '../identity/delivery_assignment_id_generator.dart';
import 'record_courier_event.dart';

/// Moves an in-progress [Delivery] (accepted or already at the restaurant)
/// off its current courier and onto [newCourierId] — "reassignment
/// preserves history": the superseded [DeliveryAssignment] is left
/// untouched (still shows its true historical `accepted` status, never
/// mutated to look cancelled), and a brand-new `DeliveryAssignment` record
/// is created for [newCourierId], directly accepted (mirrors
/// [ManuallyAssignDelivery] — a manager driving an urgent reassignment
/// does not wait for the new courier's separate acceptance).
///
/// Requires [overrideReason] (non-empty — same "actor + reason mandatory"
/// rule as [ManuallyAssignDelivery]).
class ReassignDelivery {
  const ReassignDelivery({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required DeliveryAssignmentIdGenerator assignmentIdGenerator,
    required DeliveryAssignmentAttemptIdGenerator attemptIdGenerator,
    required DeliveryRepository deliveryRepository,
    required DeliveryAssignmentRepository assignmentRepository,
    required DeliveryAssignmentAttemptRepository attemptRepository,
    required CourierAvailabilityRepository availabilityRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _assignmentIdGenerator = assignmentIdGenerator,
        _attemptIdGenerator = attemptIdGenerator,
        _deliveryRepository = deliveryRepository,
        _assignmentRepository = assignmentRepository,
        _attemptRepository = attemptRepository,
        _availabilityRepository = availabilityRepository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final DeliveryAssignmentIdGenerator _assignmentIdGenerator;
  final DeliveryAssignmentAttemptIdGenerator _attemptIdGenerator;
  final DeliveryRepository _deliveryRepository;
  final DeliveryAssignmentRepository _assignmentRepository;
  final DeliveryAssignmentAttemptRepository _attemptRepository;
  final CourierAvailabilityRepository _availabilityRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;

  Future<DeliveryAssignment> call({
    required String deliveryId,
    required int expectedRevision,
    required String newCourierId,
    required String overrideReason,
    required String performedByStaffId,
    String? deviceId,
  }) async {
    if (overrideReason.trim().isEmpty) {
      throw const ManualOverrideReasonRequiredViolation();
    }

    final delivery = await _deliveryRepository.findById(deliveryId);
    if (delivery == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Delivery',
        id: deliveryId,
      );
    }
    if (delivery.revision != expectedRevision) {
      throw StaleCourierRevisionViolation(
        entityId: deliveryId,
        expectedRevision: expectedRevision,
        actualRevision: delivery.revision,
      );
    }
    if (!DeliveryStatusTransitions.canTransition(
        delivery.status, DeliveryStatus.reassigned)) {
      throw InvalidDeliveryTransitionViolation(
        fromStatusName: delivery.status.name,
        toStatusName: DeliveryStatus.reassigned.name,
      );
    }

    const action = PosAuthorizedAction.reassignDelivery;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'deliveryId': deliveryId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final previousCourierId = delivery.courierId;
    if (previousCourierId != null) {
      final previousAvailability =
          await _availabilityRepository.findByCourierId(previousCourierId);
      if (previousAvailability != null &&
          previousAvailability.activeAssignmentCount > 0) {
        await _availabilityRepository.save(previousAvailability.copyWith(
          activeAssignmentCount: previousAvailability.activeAssignmentCount - 1,
          updatedAt: now,
          revision: previousAvailability.revision + 1,
        ));
      }
    }

    final reassigned = delivery.copyWith(
      status: DeliveryStatus.reassigned,
      revision: delivery.revision + 1,
    );
    await _deliveryRepository.save(reassigned);

    final requeued = reassigned.copyWith(
      status: DeliveryStatus.readyForAssignment,
      clearCourierId: true,
      clearAssignmentId: true,
      revision: reassigned.revision + 1,
    );
    await _deliveryRepository.save(requeued);

    final newAssignment = DeliveryAssignment(
      id: _assignmentIdGenerator.nextAssignmentId(),
      deliveryId: deliveryId,
      courierId: newCourierId,
      status: DeliveryAssignmentStatus.accepted,
      offeredAt: now,
      respondedAt: now,
      isManualOverride: true,
      overrideReason: overrideReason,
      overriddenByStaffId: performedByStaffId,
      revision: 1,
    );
    await _assignmentRepository.save(newAssignment);

    await _attemptRepository.append(DeliveryAssignmentAttempt(
      id: _attemptIdGenerator.nextAttemptId(),
      deliveryId: deliveryId,
      assignmentId: newAssignment.id,
      courierId: newCourierId,
      attemptedAt: now,
    ));

    final assigned = requeued.copyWith(
      status: DeliveryStatus.assigned,
      courierId: newCourierId,
      currentAssignmentId: newAssignment.id,
      revision: requeued.revision + 1,
    );
    await _deliveryRepository.save(assigned);

    final accepted = assigned.copyWith(
      status: DeliveryStatus.accepted,
      revision: assigned.revision + 1,
    );
    await _deliveryRepository.save(accepted);

    final newAvailability =
        await _availabilityRepository.findByCourierId(newCourierId);
    if (newAvailability != null) {
      await _availabilityRepository.save(newAvailability.copyWith(
        activeAssignmentCount: newAvailability.activeAssignmentCount + 1,
        updatedAt: now,
        revision: newAvailability.revision + 1,
      ));
    }

    final event = await _recordCourierEvent(
      branchId: delivery.branchId,
      courierId: newCourierId,
      deliveryId: delivery.id,
      assignmentId: newAssignment.id,
      type: CourierEventType.deliveryReassigned,
      idempotencyKey: '${newAssignment.id}-reassign',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: {
        if (previousCourierId != null) 'previousCourierId': previousCourierId,
      },
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: delivery.branchId,
      actorStaffId: performedByStaffId,
      courierId: newCourierId,
      deviceId: deviceId,
      orderId: delivery.orderId.value,
      deliveryId: delivery.id,
      assignmentId: newAssignment.id,
      type: CourierAuditEventType.reassigned,
      description: 'Reassigned from '
          '"${previousCourierId ?? 'unassigned'}" to "$newCourierId"',
      previousStateName: previousCourierId,
      newStateName: newCourierId,
      reason: overrideReason,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return newAssignment;
  }
}
