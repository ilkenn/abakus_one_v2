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

/// A manager directly assigns a [Delivery] to a specific courier,
/// **bypassing [DispatchScorer]** — "manual override requires actor and
/// reason." Unlike [OfferDeliveryAssignment]'s offer-then-respond flow,
/// a manual assignment lands directly at [DeliveryAssignmentStatus.accepted]
/// (a manager physically directing a courier does not need a separate
/// courier-side acceptance step) — a documented design simplification,
/// see `docs/decisions.md` ADR-017.
///
/// Requires [Delivery.status] to be [DeliveryStatus.readyForAssignment]
/// and [overrideReason] to be non-empty (throws
/// [ManualOverrideReasonRequiredViolation] otherwise).
class ManuallyAssignDelivery {
  const ManuallyAssignDelivery({
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
    required String courierId,
    required String overrideReason,
    required String overriddenByStaffId,
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
    if (delivery.currentAssignmentId != null) {
      throw DeliveryAlreadyAssignedViolation(deliveryId: deliveryId);
    }
    if (delivery.status != DeliveryStatus.readyForAssignment) {
      throw InvalidDeliveryTransitionViolation(
        fromStatusName: delivery.status.name,
        toStatusName: DeliveryStatus.accepted.name,
      );
    }

    const action = PosAuthorizedAction.manuallyAssignDelivery;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: overriddenByStaffId,
      context: {'deliveryId': deliveryId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final assignment = DeliveryAssignment(
      id: _assignmentIdGenerator.nextAssignmentId(),
      deliveryId: deliveryId,
      courierId: courierId,
      status: DeliveryAssignmentStatus.accepted,
      offeredAt: now,
      respondedAt: now,
      isManualOverride: true,
      overrideReason: overrideReason,
      overriddenByStaffId: overriddenByStaffId,
      revision: 1,
    );
    await _assignmentRepository.save(assignment);

    await _attemptRepository.append(DeliveryAssignmentAttempt(
      id: _attemptIdGenerator.nextAttemptId(),
      deliveryId: deliveryId,
      assignmentId: assignment.id,
      courierId: courierId,
      attemptedAt: now,
    ));

    final assigned = delivery.copyWith(
      status: DeliveryStatus.assigned,
      courierId: courierId,
      currentAssignmentId: assignment.id,
      revision: delivery.revision + 1,
    );
    await _deliveryRepository.save(assigned);

    final accepted = assigned.copyWith(
      status: DeliveryStatus.accepted,
      revision: assigned.revision + 1,
    );
    await _deliveryRepository.save(accepted);

    final availability =
        await _availabilityRepository.findByCourierId(courierId);
    if (availability != null) {
      await _availabilityRepository.save(availability.copyWith(
        activeAssignmentCount: availability.activeAssignmentCount + 1,
        updatedAt: now,
        revision: availability.revision + 1,
      ));
    }

    final event = await _recordCourierEvent(
      branchId: delivery.branchId,
      courierId: courierId,
      deliveryId: delivery.id,
      assignmentId: assignment.id,
      type: CourierEventType.assignmentAccepted,
      idempotencyKey: '${assignment.id}-manual',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: {'isManualOverride': 'true'},
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: delivery.branchId,
      actorStaffId: overriddenByStaffId,
      courierId: courierId,
      deviceId: deviceId,
      orderId: delivery.orderId.value,
      deliveryId: delivery.id,
      assignmentId: assignment.id,
      type: CourierAuditEventType.manuallyAssigned,
      description: 'Manually assigned to courier "$courierId"',
      previousStateName: DeliveryStatus.readyForAssignment.name,
      newStateName: DeliveryStatus.accepted.name,
      reason: overrideReason,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return assignment;
  }
}
