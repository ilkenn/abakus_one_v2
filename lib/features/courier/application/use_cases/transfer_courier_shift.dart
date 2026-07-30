import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/courier_shift_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/shift/courier_shift.dart';
import '../../domain/shift/courier_shift_status.dart';
import 'reassign_delivery.dart';
import 'transition_courier_shift.dart';

/// A manager hands a courier's remaining shift responsibilities to
/// another courier — Sprint 5C Part 7's "shift transfer." Composes two
/// existing, unmodified use cases rather than reimplementing either:
/// every one of the source courier's active deliveries is reassigned via
/// [ReassignDelivery] (preserving that use case's own full audit/
/// idempotency/authorization behavior), then the source shift is moved to
/// [CourierShiftStatus.suspended] via [TransitionCourierShift] —
/// deliberately **not** `completed`, since `TransitionCourierShift`
/// itself requires zero active deliveries to reach `completed`, and a
/// transferring courier's shift record should remain resumable/reviewable
/// by a manager rather than silently finalized. Manager-only
/// ([PosAuthorizedAction.transferCourierShift]), requires a non-empty
/// [reason], and appends its own dedicated
/// [CourierAuditEventType.shiftTransferred] entry on top of what
/// `ReassignDelivery`/`TransitionCourierShift` already record.
class TransferCourierShift {
  const TransferCourierShift({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierShiftRepository shiftRepository,
    required DeliveryRepository deliveryRepository,
    required ReassignDelivery reassignDelivery,
    required TransitionCourierShift transitionCourierShift,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _shiftRepository = shiftRepository,
        _deliveryRepository = deliveryRepository,
        _reassignDelivery = reassignDelivery,
        _transitionCourierShift = transitionCourierShift,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierShiftRepository _shiftRepository;
  final DeliveryRepository _deliveryRepository;
  final ReassignDelivery _reassignDelivery;
  final TransitionCourierShift _transitionCourierShift;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<CourierShift> call({
    required String fromShiftId,
    required String toCourierId,
    required String reason,
    required String performedByStaffId,
  }) async {
    if (reason.trim().isEmpty) {
      throw const ManualOverrideReasonRequiredViolation();
    }

    const action = PosAuthorizedAction.transferCourierShift;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'shiftId': fromShiftId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final shift = await _shiftRepository.findById(fromShiftId);
    if (shift == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'CourierShift',
        id: fromShiftId,
      );
    }
    if (shift.status != CourierShiftStatus.active) {
      throw InvalidCourierShiftTransitionViolation(
        fromStatusName: shift.status.name,
        toStatusName: CourierShiftStatus.suspended.name,
      );
    }

    final activeDeliveries =
        await _deliveryRepository.findActiveByCourierId(shift.courierId);
    for (final delivery in activeDeliveries) {
      await _reassignDelivery(
        deliveryId: delivery.id,
        expectedRevision: delivery.revision,
        newCourierId: toCourierId,
        overrideReason: 'Shift transfer: $reason',
        performedByStaffId: performedByStaffId,
      );
    }

    final updatedShift = await _transitionCourierShift(
      shiftId: fromShiftId,
      to: CourierShiftStatus.suspended,
      performedByStaffId: performedByStaffId,
      reason: reason,
    );

    final now = _clock.now();
    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${shift.id}-transfer-${updatedShift.revision}',
      branchId: shift.branchId,
      actorStaffId: performedByStaffId,
      courierId: shift.courierId,
      shiftId: shift.id,
      type: CourierAuditEventType.shiftTransferred,
      description: 'Shift transferred from "${shift.courierId}" to '
          '"$toCourierId" (${activeDeliveries.length} deliveries moved): '
          '$reason',
      reason: reason,
      timestamp: now,
      correlationId: '${shift.id}-transfer-${updatedShift.revision}',
    ));

    return updatedShift;
  }
}
