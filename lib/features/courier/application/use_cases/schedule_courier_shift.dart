import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/courier_shift_repository.dart';
import '../../data/courier_shift_schedule_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/compensation/courier_shift_schedule.dart';
import '../identity/courier_shift_schedule_id_generator.dart';

/// Sets a manager-planned start/end time for a [CourierShift] — the
/// "ScheduledShiftStart"/scheduled-end the earnings-window business rules
/// reference. Additive: never writes to `CourierShift` itself (see
/// `CourierShiftSchedule`'s own doc comment for why). Append-only — a
/// manager rescheduling before the shift starts creates a new revision;
/// [findLatestByShiftId] always resolves the most recent one.
class ScheduleCourierShift {
  const ScheduleCourierShift({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierShiftScheduleIdGenerator idGenerator,
    required CourierShiftRepository shiftRepository,
    required CourierShiftScheduleRepository scheduleRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _shiftRepository = shiftRepository,
        _scheduleRepository = scheduleRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierShiftScheduleIdGenerator _idGenerator;
  final CourierShiftRepository _shiftRepository;
  final CourierShiftScheduleRepository _scheduleRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<CourierShiftSchedule> call({
    required String shiftId,
    required DateTime scheduledStart,
    required DateTime scheduledEnd,
    required String performedByStaffId,
  }) async {
    final shift = await _shiftRepository.findById(shiftId);
    if (shift == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'CourierShift',
        id: shiftId,
      );
    }
    if (!scheduledEnd.isAfter(scheduledStart)) {
      throw const InvalidCompensationConfigurationViolation(
        reason: 'scheduledEnd must be strictly after scheduledStart',
      );
    }

    const action = PosAuthorizedAction.scheduleCourierShift;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'shiftId': shiftId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final schedule = CourierShiftSchedule(
      id: _idGenerator.nextScheduleId(),
      shiftId: shiftId,
      courierId: shift.courierId,
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledEnd,
      setByStaffId: performedByStaffId,
      setAt: now,
    );
    await _scheduleRepository.append(schedule);

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${schedule.id}-audit',
      branchId: shift.branchId,
      actorStaffId: performedByStaffId,
      courierId: shift.courierId,
      shiftId: shiftId,
      type: CourierAuditEventType.shiftScheduled,
      description: 'Shift scheduled $scheduledStart - $scheduledEnd',
      timestamp: now,
      correlationId: schedule.id,
    ));

    return schedule;
  }
}
