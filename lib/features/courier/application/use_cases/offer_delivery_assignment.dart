import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/delivery_assignment_attempt_repository.dart';
import '../../data/delivery_assignment_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/delivery/delivery.dart';
import '../../domain/delivery/delivery_assignment.dart';
import '../../domain/delivery/delivery_assignment_attempt.dart';
import '../../domain/delivery/delivery_assignment_status.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/dispatch/dispatch_scorer.dart';
import '../../domain/dispatch/dispatch_scoring_input.dart';
import '../../domain/events/courier_event_type.dart';
import '../identity/delivery_assignment_attempt_id_generator.dart';
import '../identity/delivery_assignment_id_generator.dart';
import 'record_courier_event.dart';

/// Ranks [candidates] with [DispatchScorer] and offers the delivery to the
/// top-ranked eligible one — the automatic-dispatch path. Purely a
/// rule-based, in-memory ranking (`DispatchScorer`'s own documented
/// boundary) — **not production route optimization**.
///
/// The caller assembles [candidates] (reading `CourierAvailability`/
/// location data itself) — this use case only ranks and offers; it never
/// reaches into other repositories to build scoring inputs itself, so it
/// stays trivially testable with hand-built [DispatchScoringInput] lists.
///
/// **One delivery cannot have two active accepted couriers**: throws
/// [DeliveryAlreadyAssignedViolation] if [Delivery.currentAssignmentId] is
/// already set. Requires [Delivery.status] to be
/// [DeliveryStatus.readyForAssignment].
class OfferDeliveryAssignment {
  const OfferDeliveryAssignment({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required DeliveryAssignmentIdGenerator assignmentIdGenerator,
    required DeliveryAssignmentAttemptIdGenerator attemptIdGenerator,
    required DeliveryRepository deliveryRepository,
    required DeliveryAssignmentRepository assignmentRepository,
    required DeliveryAssignmentAttemptRepository attemptRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _assignmentIdGenerator = assignmentIdGenerator,
        _attemptIdGenerator = attemptIdGenerator,
        _deliveryRepository = deliveryRepository,
        _assignmentRepository = assignmentRepository,
        _attemptRepository = attemptRepository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final DeliveryAssignmentIdGenerator _assignmentIdGenerator;
  final DeliveryAssignmentAttemptIdGenerator _attemptIdGenerator;
  final DeliveryRepository _deliveryRepository;
  final DeliveryAssignmentRepository _assignmentRepository;
  final DeliveryAssignmentAttemptRepository _attemptRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;

  Future<DeliveryAssignment> call({
    required String deliveryId,
    required int expectedRevision,
    required List<DispatchScoringInput> candidates,
    required String performedByStaffId,
    String? deviceId,
  }) async {
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
    if (!DeliveryStatusTransitions.canTransition(
        delivery.status, DeliveryStatus.assigned)) {
      throw InvalidDeliveryTransitionViolation(
        fromStatusName: delivery.status.name,
        toStatusName: DeliveryStatus.assigned.name,
      );
    }

    final ranked = DispatchScorer.rank(candidates);
    final eligible = ranked.where((r) => r.isEligible).toList();
    final winner = eligible.isEmpty ? null : eligible.first;
    if (winner == null) {
      throw CourierNotAvailableViolation(
        courierId: '',
        reason: 'no eligible dispatch candidate for delivery "$deliveryId"',
      );
    }

    const action = PosAuthorizedAction.offerDeliveryAssignment;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'deliveryId': deliveryId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final assignment = DeliveryAssignment(
      id: _assignmentIdGenerator.nextAssignmentId(),
      deliveryId: deliveryId,
      courierId: winner.courierId,
      status: DeliveryAssignmentStatus.offered,
      offeredAt: now,
      revision: 1,
    );
    await _assignmentRepository.save(assignment);

    await _attemptRepository.append(DeliveryAssignmentAttempt(
      id: _attemptIdGenerator.nextAttemptId(),
      deliveryId: deliveryId,
      assignmentId: assignment.id,
      courierId: winner.courierId,
      scoringSnapshot: winner.breakdown,
      attemptedAt: now,
    ));

    final updatedDelivery = delivery.copyWith(
      status: DeliveryStatus.assigned,
      courierId: winner.courierId,
      currentAssignmentId: assignment.id,
      revision: delivery.revision + 1,
    );
    await _deliveryRepository.save(updatedDelivery);

    final event = await _recordCourierEvent(
      branchId: delivery.branchId,
      courierId: winner.courierId,
      deliveryId: delivery.id,
      assignmentId: assignment.id,
      type: CourierEventType.assignmentOffered,
      idempotencyKey: '${assignment.id}-offer',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: {'score': winner.score.toStringAsFixed(4)},
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: delivery.branchId,
      actorStaffId: performedByStaffId,
      courierId: winner.courierId,
      deviceId: deviceId,
      orderId: delivery.orderId.value,
      deliveryId: delivery.id,
      assignmentId: assignment.id,
      type: CourierAuditEventType.assignmentOffered,
      description: 'Assignment offered to courier "${winner.courierId}"',
      previousStateName: DeliveryStatus.readyForAssignment.name,
      newStateName: DeliveryStatus.assigned.name,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return assignment;
  }
}
