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
import 'courier_location_availability_guard.dart';
import 'record_courier_event.dart';

/// Changes a courier's [CourierAvailabilityStatus] — append-only via
/// revision (availability history stays auditable).
///
/// **Reaching [CourierAvailabilityStatus.available] requires an active,
/// approved [CourierShift]** — throws [CourierShiftRequiredViolation]
/// otherwise. **A suspended courier can never become available** — throws
/// [CourierNotAvailableViolation]. Never touches financial settlement.
///
/// **Sprint 5B**: [locationGuard], when supplied, requires location to be
/// available before a courier may reach [CourierAvailabilityStatus.online]
/// or [CourierAvailabilityStatus.available] — "a courier cannot become
/// online, available... while location is unavailable." Deliberately
/// **not** checked for [CourierAvailabilityStatus.temporarilyUnavailable]
/// (or any other target) — `ReportCourierLocationAvailability` itself
/// calls this use case to *set* `temporarilyUnavailable` precisely when
/// location becomes unavailable, and gating that transition on location
/// being available would make the rule unsatisfiable. `null` (the
/// default, and every existing call site predating Sprint 5B) skips the
/// check entirely.
class SetCourierAvailability {
  const SetCourierAvailability({
    required Clock clock,
    required CourierShiftRepository shiftRepository,
    required CourierAvailabilityRepository availabilityRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
    CourierLocationAvailabilityGuard? locationGuard,
  })  : _clock = clock,
        _shiftRepository = shiftRepository,
        _availabilityRepository = availabilityRepository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent,
        _locationGuard = locationGuard;

  final Clock _clock;
  final CourierShiftRepository _shiftRepository;
  final CourierAvailabilityRepository _availabilityRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;
  final CourierLocationAvailabilityGuard? _locationGuard;

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
    if (to == CourierAvailabilityStatus.online ||
        to == CourierAvailabilityStatus.available) {
      await _locationGuard?.assertAvailable(courierId: courierId);
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
