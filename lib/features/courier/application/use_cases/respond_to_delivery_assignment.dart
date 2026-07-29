import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_availability_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/delivery_assignment_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/delivery/delivery_assignment.dart';
import '../../domain/delivery/delivery_assignment_status.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/events/courier_event_type.dart';
import '../../domain/feedback/courier_feedback_tag.dart';
import 'courier_location_availability_guard.dart';
import 'record_courier_event.dart';

/// The courier's accept/reject response to an offered [DeliveryAssignment]
/// — unified, mirrors `ReviewCourierShift`'s accept/reject shape.
///
/// **Rejection requires a predefined reason tag** — [rejectionReasonCode]
/// is validated against [CourierFeedbackTag] names (per
/// [DeliveryAssignment.rejectionReasonCode]'s own doc comment); a
/// non-matching value throws [InvalidAssignmentRejectionReasonViolation].
///
/// On accept: [Delivery] moves to [DeliveryStatus.accepted] and the
/// courier's [CourierAvailability.activeAssignmentCount] is incremented.
/// On reject: [Delivery] moves through [DeliveryStatus.assignmentRejected]
/// and is immediately requeued to [DeliveryStatus.readyForAssignment] (a
/// second saved revision, mirroring `CreateDelivery`'s double-revision
/// pattern) — "reassignment/re-offering preserves history," so the
/// rejected [DeliveryAssignment] itself is left untouched, not deleted.
///
/// **Sprint 5B**: [locationGuard], when supplied, requires location to be
/// available before an **accepted** response is allowed — "a courier
/// cannot... accept an assignment... while location is unavailable."
/// Rejecting is never gated (a courier with no working location must
/// still be able to decline). `null` (the default) skips the check.
class RespondToDeliveryAssignment {
  const RespondToDeliveryAssignment({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required DeliveryAssignmentRepository assignmentRepository,
    required DeliveryRepository deliveryRepository,
    required CourierAvailabilityRepository availabilityRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
    CourierLocationAvailabilityGuard? locationGuard,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _assignmentRepository = assignmentRepository,
        _deliveryRepository = deliveryRepository,
        _availabilityRepository = availabilityRepository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent,
        _locationGuard = locationGuard;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final DeliveryAssignmentRepository _assignmentRepository;
  final DeliveryRepository _deliveryRepository;
  final CourierAvailabilityRepository _availabilityRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;
  final CourierLocationAvailabilityGuard? _locationGuard;

  Future<DeliveryAssignment> call({
    required String assignmentId,
    required String courierId,
    required bool accept,
    String? rejectionReasonCode,
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
    if (assignment.courierId != courierId) {
      throw DeliveryNotAssignedToCourierViolation(
        deliveryId: assignment.deliveryId,
        courierId: courierId,
      );
    }
    if (assignment.status != DeliveryAssignmentStatus.offered) {
      throw InvalidDeliveryAssignmentTransitionViolation(
        fromStatusName: assignment.status.name,
        toStatusName: accept ? 'accepted' : 'rejected',
      );
    }
    if (!accept &&
        !CourierFeedbackTag.values
            .map((t) => t.name)
            .contains(rejectionReasonCode)) {
      throw InvalidAssignmentRejectionReasonViolation(
        reasonCode: rejectionReasonCode ?? '',
      );
    }
    if (accept) {
      await _locationGuard?.assertAvailable(
        courierId: courierId,
        deliveryId: assignment.deliveryId,
      );
    }

    final delivery = await _deliveryRepository.findById(assignment.deliveryId);
    if (delivery == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Delivery',
        id: assignment.deliveryId,
      );
    }

    const action = PosAuthorizedAction.respondToDeliveryAssignment;
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
      status: accept
          ? DeliveryAssignmentStatus.accepted
          : DeliveryAssignmentStatus.rejected,
      respondedAt: now,
      rejectionReasonCode: accept ? null : rejectionReasonCode,
      revision: assignment.revision + 1,
    );
    await _assignmentRepository.save(updatedAssignment);

    if (accept) {
      final updatedDelivery = delivery.copyWith(
        status: DeliveryStatus.accepted,
        revision: delivery.revision + 1,
      );
      await _deliveryRepository.save(updatedDelivery);

      final availability =
          await _availabilityRepository.findByCourierId(courierId);
      if (availability != null) {
        await _availabilityRepository.save(availability.copyWith(
          activeAssignmentCount: availability.activeAssignmentCount + 1,
          updatedAt: now,
          revision: availability.revision + 1,
        ));
      }
    } else {
      final rejected = delivery.copyWith(
        status: DeliveryStatus.assignmentRejected,
        revision: delivery.revision + 1,
      );
      await _deliveryRepository.save(rejected);

      final requeued = rejected.copyWith(
        status: DeliveryStatus.readyForAssignment,
        clearCourierId: true,
        clearAssignmentId: true,
        revision: rejected.revision + 1,
      );
      await _deliveryRepository.save(requeued);
    }

    final event = await _recordCourierEvent(
      branchId: delivery.branchId,
      courierId: courierId,
      deliveryId: delivery.id,
      assignmentId: assignment.id,
      type: accept
          ? CourierEventType.assignmentAccepted
          : CourierEventType.assignmentRejected,
      idempotencyKey: '${assignment.id}-response',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: {
        if (!accept && rejectionReasonCode != null)
          'rejectionReasonCode': rejectionReasonCode,
      },
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: delivery.branchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      deviceId: deviceId,
      orderId: delivery.orderId.value,
      deliveryId: delivery.id,
      assignmentId: assignment.id,
      type: accept
          ? CourierAuditEventType.assignmentAccepted
          : CourierAuditEventType.assignmentRejected,
      description: accept
          ? 'Assignment accepted by courier "$courierId"'
          : 'Assignment rejected by courier "$courierId": '
              '$rejectionReasonCode',
      previousStateName: DeliveryAssignmentStatus.offered.name,
      newStateName: updatedAssignment.status.name,
      reason: accept ? null : rejectionReasonCode,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return updatedAssignment;
  }
}
