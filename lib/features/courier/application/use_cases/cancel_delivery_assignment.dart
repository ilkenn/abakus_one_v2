import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/delivery_assignment_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/delivery/delivery_assignment.dart';
import '../../domain/delivery/delivery_assignment_status.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/events/courier_event_type.dart';
import 'record_courier_event.dart';

/// Ends a still-[DeliveryAssignmentStatus.offered] offer without a courier
/// response — either manager-cancelled ([isExpiry] `false`, the
/// `CancelDeliveryAssignment` brief use case) or system-timed-out
/// ([isExpiry] `true`, the `ExpireDeliveryAssignment` brief use case).
/// Unified into one use case (mirrors `ChangeCourierRegistryStatus`'s
/// activate/suspend/archive consolidation) since both share every step
/// except which [CourierEventType]/[CourierAuditEventType] they record —
/// see `docs/decisions.md` ADR-017.
///
/// Only a still-[DeliveryAssignmentStatus.offered] assignment can be
/// cancelled/expired here — an already-[DeliveryAssignmentStatus.accepted]
/// assignment must go through [ReassignDelivery] instead (a courier who
/// already accepted needs a proper reassignment, not a bare cancellation).
///
/// The [Delivery] is requeued to [DeliveryStatus.readyForAssignment] via
/// [DeliveryStatus.assignmentExpired] (double revision, mirrors
/// [RespondToDeliveryAssignment]'s rejection path) regardless of
/// [isExpiry] — "cancel this offer" and "this offer timed out" both mean
/// the same thing for the delivery's own state machine.
class CancelDeliveryAssignment {
  const CancelDeliveryAssignment({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required DeliveryAssignmentRepository assignmentRepository,
    required DeliveryRepository deliveryRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _assignmentRepository = assignmentRepository,
        _deliveryRepository = deliveryRepository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final DeliveryAssignmentRepository _assignmentRepository;
  final DeliveryRepository _deliveryRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;

  Future<DeliveryAssignment> call({
    required String assignmentId,
    bool isExpiry = false,
    String? reason,
    required String performedByStaffId,
    String? deviceId,
  }) async {
    final assignment = await _assignmentRepository.findById(assignmentId);
    if (assignment == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'DeliveryAssignment',
        id: assignmentId,
      );
    }
    if (assignment.status != DeliveryAssignmentStatus.offered) {
      throw InvalidDeliveryAssignmentTransitionViolation(
        fromStatusName: assignment.status.name,
        toStatusName:
            isExpiry ? DeliveryAssignmentStatus.expired.name : 'cancelled',
      );
    }

    final delivery = await _deliveryRepository.findById(assignment.deliveryId);
    if (delivery == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Delivery',
        id: assignment.deliveryId,
      );
    }

    const action = PosAuthorizedAction.cancelDeliveryAssignment;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'assignmentId': assignmentId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final updatedAssignment = assignment.copyWith(
      status: isExpiry
          ? DeliveryAssignmentStatus.expired
          : DeliveryAssignmentStatus.cancelled,
      respondedAt: now,
      revision: assignment.revision + 1,
    );
    await _assignmentRepository.save(updatedAssignment);

    final expiredDeliveryStatus = isExpiry
        ? DeliveryStatus.assignmentExpired
        : DeliveryStatus.assignmentRejected;
    final intermediate = delivery.copyWith(
      status: expiredDeliveryStatus,
      revision: delivery.revision + 1,
    );
    await _deliveryRepository.save(intermediate);

    final requeued = intermediate.copyWith(
      status: DeliveryStatus.readyForAssignment,
      clearCourierId: true,
      clearAssignmentId: true,
      revision: intermediate.revision + 1,
    );
    await _deliveryRepository.save(requeued);

    final event = await _recordCourierEvent(
      branchId: delivery.branchId,
      courierId: assignment.courierId,
      deliveryId: delivery.id,
      assignmentId: assignment.id,
      type: isExpiry
          ? CourierEventType.assignmentExpired
          : CourierEventType.assignmentCancelled,
      idempotencyKey: '${assignment.id}-${isExpiry ? 'expire' : 'cancel'}',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: {if (reason != null) 'reason': reason},
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: delivery.branchId,
      actorStaffId: performedByStaffId,
      courierId: assignment.courierId,
      deviceId: deviceId,
      orderId: delivery.orderId.value,
      deliveryId: delivery.id,
      assignmentId: assignment.id,
      type: CourierAuditEventType.assignmentCancelled,
      description: isExpiry
          ? 'Assignment offer expired'
          : 'Assignment cancelled${reason == null ? '' : ': $reason'}',
      previousStateName: DeliveryAssignmentStatus.offered.name,
      newStateName: updatedAssignment.status.name,
      reason: reason,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return updatedAssignment;
  }
}
