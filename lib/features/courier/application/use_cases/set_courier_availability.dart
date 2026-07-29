import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/courier_availability_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/courier_shift_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/availability/courier_availability.dart';
import '../../domain/availability/courier_availability_status.dart';
import '../../domain/events/courier_event_type.dart';
import '../../domain/shift/courier_shift_status.dart';
import 'record_courier_event.dart';

/// Changes a courier's [CourierAvailabilityStatus] — append-only via
/// revision (availability history stays auditable).
///
/// **Reaching [CourierAvailabilityStatus.available] requires an active,
/// approved [CourierShift]** — throws [CourierShiftRequiredViolation]
/// otherwise. **A suspended courier can never become available** — throws
/// [CourierNotAvailableViolation]. Never touches financial settlement.
class SetCourierAvailability {
  const SetCourierAvailability({
    required Clock clock,
    required CourierShiftRepository shiftRepository,
    required CourierAvailabilityRepository availabilityRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
  })  : _clock = clock,
        _shiftRepository = shiftRepository,
        _availabilityRepository = availabilityRepository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent;

  final Clock _clock;
  final CourierShiftRepository _shiftRepository;
  final CourierAvailabilityRepository _availabilityRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;

  Future<CourierAvailability> call({
    required String courierId,
    required CourierAvailabilityStatus to,
    required int capacity,
    required String performedByStaffId,
  }) async {
    final current = await _availabilityRepository.findByCourierId(courierId);
    if (current?.status == CourierAvailabilityStatus.suspended &&
        to != CourierAvailabilityStatus.suspended) {
      throw CourierNotAvailableViolation(
        courierId: courierId,
        reason: 'courier is suspended',
      );
    }

    final activeShift = await _shiftRepository.findActiveByCourierId(courierId);
    if (to == CourierAvailabilityStatus.available &&
        (activeShift == null ||
            activeShift.status != CourierShiftStatus.active)) {
      throw CourierShiftRequiredViolation(courierId: courierId);
    }

    final now = _clock.now();
    final updated = CourierAvailability(
      courierId: courierId,
      shiftId: activeShift?.id ?? current?.shiftId ?? '',
      status: to,
      activeAssignmentCount: current?.activeAssignmentCount ?? 0,
      capacity: capacity,
      updatedAt: now,
      revision: (current?.revision ?? 0) + 1,
    );
    await _availabilityRepository.save(updated);

    final event = await _recordCourierEvent(
      branchId: activeShift?.branchId ?? '',
      courierId: courierId,
      type: CourierEventType.availabilityChanged,
      idempotencyKey: '$courierId-availability-rev${updated.revision}',
      occurredAt: now,
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: activeShift?.branchId ?? '',
      actorStaffId: performedByStaffId,
      courierId: courierId,
      type: CourierAuditEventType.availabilityChanged,
      description: 'Availability: ${current?.status.name ?? 'none'} -> '
          '${to.name}',
      previousStateName: current?.status.name,
      newStateName: to.name,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return updated;
  }
}
