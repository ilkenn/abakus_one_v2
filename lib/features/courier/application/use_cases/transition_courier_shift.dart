import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/courier_shift_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/events/courier_event_type.dart';
import '../../domain/shift/courier_shift.dart';
import '../../domain/shift/courier_shift_status.dart';
import 'courier_location_availability_guard.dart';
import 'record_courier_event.dart';

/// Transitions a [CourierShift] through the remainder of its lifecycle
/// (approved -> active -> ending -> completed, plus cancelled/suspended)
/// — one use case, mirrors `TransitionKitchenWorkItem`.
///
/// **Ending a shift accounts for active deliveries**: reaching
/// [CourierShiftStatus.completed] from [CourierShiftStatus.ending]
/// requires zero active deliveries for the courier (checked via
/// [DeliveryRepository], not a closure — same feature, intra-feature
/// composition). **Shift completion never automatically closes financial
/// settlement** — this use case never touches `CourierSettlementSession`
/// (Sprint 3F) at all.
///
/// **Sprint 5B**: [locationGuard], when supplied, requires location to be
/// available before a shift may reach [CourierShiftStatus.active] —
/// "location permission and device location service are mandatory before
/// shift activation." `null` (the default, and every existing call site
/// predating Sprint 5B) skips the check entirely — fully backward
/// compatible.
class TransitionCourierShift {
  const TransitionCourierShift({
    required Clock clock,
    required CourierShiftRepository repository,
    required DeliveryRepository deliveryRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
    CourierLocationAvailabilityGuard? locationGuard,
  })  : _clock = clock,
        _repository = repository,
        _deliveryRepository = deliveryRepository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent,
        _locationGuard = locationGuard;

  final Clock _clock;
  final CourierShiftRepository _repository;
  final DeliveryRepository _deliveryRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;
  final CourierLocationAvailabilityGuard? _locationGuard;

  static CourierAuditEventType _auditTypeFor(CourierShiftStatus to) {
    switch (to) {
      case CourierShiftStatus.active:
        return CourierAuditEventType.shiftStarted;
      case CourierShiftStatus.ending:
      case CourierShiftStatus.completed:
        return CourierAuditEventType.shiftEnded;
      case CourierShiftStatus.cancelled:
        return CourierAuditEventType.shiftCancelled;
      case CourierShiftStatus.scheduled:
      case CourierShiftStatus.awaitingManagerApproval:
      case CourierShiftStatus.approved:
      case CourierShiftStatus.rejected:
      case CourierShiftStatus.suspended:
        return CourierAuditEventType.shiftStarted;
    }
  }

  static CourierEventType _eventTypeFor(CourierShiftStatus to) {
    switch (to) {
      case CourierShiftStatus.active:
        return CourierEventType.shiftStarted;
      case CourierShiftStatus.ending:
        return CourierEventType.shiftEnding;
      case CourierShiftStatus.completed:
        return CourierEventType.shiftCompleted;
      case CourierShiftStatus.cancelled:
        return CourierEventType.shiftCancelled;
      case CourierShiftStatus.suspended:
        return CourierEventType.shiftSuspended;
      case CourierShiftStatus.scheduled:
      case CourierShiftStatus.awaitingManagerApproval:
      case CourierShiftStatus.approved:
      case CourierShiftStatus.rejected:
        return CourierEventType.shiftStarted;
    }
  }

  Future<CourierShift> call({
    required String shiftId,
    required CourierShiftStatus to,
    required String performedByStaffId,
    String? reason,
  }) async {
    final shift = await _repository.findById(shiftId);
    if (shift == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'CourierShift',
        id: shiftId,
      );
    }
    if (!CourierShiftStatusTransitions.canTransition(shift.status, to)) {
      throw InvalidCourierShiftTransitionViolation(
        fromStatusName: shift.status.name,
        toStatusName: to.name,
      );
    }
    if (to == CourierShiftStatus.completed) {
      final activeDeliveries =
          await _deliveryRepository.findActiveByCourierId(shift.courierId);
      if (activeDeliveries.isNotEmpty) {
        throw InvalidCourierShiftTransitionViolation(
          fromStatusName: shift.status.name,
          toStatusName: to.name,
        );
      }
    }
    if (to == CourierShiftStatus.active) {
      await _locationGuard?.assertAvailable(courierId: shift.courierId);
    }

    final now = _clock.now();
    final updated = shift.copyWith(
      status: to,
      startedAt: to == CourierShiftStatus.active ? now : null,
      endedAt: to == CourierShiftStatus.completed ? now : null,
      cancellationReason: to == CourierShiftStatus.cancelled ? reason : null,
      revision: shift.revision + 1,
    );
    await _repository.save(updated);

    final event = await _recordCourierEvent(
      branchId: shift.branchId,
      courierId: shift.courierId,
      shiftId: shift.id,
      type: _eventTypeFor(to),
      idempotencyKey: '${shift.id}-rev${updated.revision}',
      occurredAt: now,
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: shift.branchId,
      actorStaffId: performedByStaffId,
      courierId: shift.courierId,
      shiftId: shift.id,
      type: _auditTypeFor(to),
      description: '${shift.status.name} -> ${to.name}',
      previousStateName: shift.status.name,
      newStateName: to.name,
      reason: reason,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return updated;
  }
}
