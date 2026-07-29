import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_compensation_profile_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/courier_shift_repository.dart';
import '../../data/courier_shift_schedule_repository.dart';
import '../../data/shift_hourly_earnings_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/compensation/shift_earnings_window_calculator.dart';
import '../../domain/compensation/shift_hourly_earnings.dart';
import '../identity/shift_hourly_earnings_id_generator.dart';

/// Computes and stores the one-time [ShiftHourlyEarnings] record for a
/// completed [CourierShift] — idempotent, mirrors
/// [CalculateDeliveryEarnings]'s exact "compute once, no update method"
/// shape.
///
/// Implements the shift-start/shift-end business rules via
/// [ShiftEarningsWindowCalculator]: earnings begin at
/// `MAX(scheduledStart, actualLogin)` — early arrival never creates extra
/// earnings, late arrival reduces payable hours — and end at the
/// scheduled end **unless** [finalDeliveryVerifiedArrivalAt] is supplied
/// (the caller-determined first verified customer-geofence arrival of a
/// delivery still active at shift end), in which case that instant is
/// used instead — "prevent intentional waiting outside the customer's
/// door." Finding that instant (`FirstVerifiedGeofenceArrivalFinder`,
/// requires the customer's coordinates) is deliberately the caller's
/// responsibility, not this use case's — kept it testable without also
/// requiring a customer-address/coordinate source, which this codebase
/// does not yet expose to the courier feature (see `docs/decisions.md`
/// ADR-018).
///
/// "Scheduled start/end" comes from `CourierShiftSchedule`
/// (`ScheduleCourierShift`) when a manager set one; falling back to the
/// shift's own actual `startedAt`/`endedAt` otherwise — meaning no early/
/// late adjustment is possible without an explicit schedule.
class CalculateShiftHourlyEarnings {
  const CalculateShiftHourlyEarnings({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required ShiftHourlyEarningsIdGenerator idGenerator,
    required CourierShiftRepository shiftRepository,
    required CourierShiftScheduleRepository scheduleRepository,
    required CourierCompensationProfileRepository compensationProfileRepository,
    required ShiftHourlyEarningsRepository earningsRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _shiftRepository = shiftRepository,
        _scheduleRepository = scheduleRepository,
        _compensationProfileRepository = compensationProfileRepository,
        _earningsRepository = earningsRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final ShiftHourlyEarningsIdGenerator _idGenerator;
  final CourierShiftRepository _shiftRepository;
  final CourierShiftScheduleRepository _scheduleRepository;
  final CourierCompensationProfileRepository _compensationProfileRepository;
  final ShiftHourlyEarningsRepository _earningsRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<ShiftHourlyEarnings> call({
    required String shiftId,
    DateTime? finalDeliveryVerifiedArrivalAt,
    required String performedByStaffId,
  }) async {
    final existing = await _earningsRepository.findByShiftId(shiftId);
    if (existing != null) return existing;

    final shift = await _shiftRepository.findById(shiftId);
    if (shift == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'CourierShift',
        id: shiftId,
      );
    }

    const action = PosAuthorizedAction.calculateCourierEarnings;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'shiftId': shiftId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final actualLogin = shift.startedAt ?? shift.requestedAt;
    final actualEnd = shift.endedAt ?? actualLogin;
    final schedule = await _scheduleRepository.findLatestByShiftId(shiftId);
    final scheduledStart = schedule?.scheduledStart ?? actualLogin;
    final scheduledEnd = schedule?.scheduledEnd ?? actualEnd;

    final earningsStartAt = ShiftEarningsWindowCalculator.determineStartAt(
      scheduledStart: scheduledStart,
      actualLogin: actualLogin,
    );
    final earningsEndAt = ShiftEarningsWindowCalculator.determineEndAt(
      scheduledEnd: scheduledEnd,
      finalDeliveryVerifiedArrivalAt: finalDeliveryVerifiedArrivalAt,
    );
    final payableDuration = ShiftEarningsWindowCalculator.payableDuration(
      start: earningsStartAt,
      end: earningsEndAt,
    );

    final profile = await _compensationProfileRepository.findEffectiveAt(
      courierId: shift.courierId,
      at: earningsEndAt,
    );
    if (profile == null) {
      throw NoEffectiveCompensationProfileViolation(
        courierId: shift.courierId,
        at: earningsEndAt,
      );
    }

    final hourlyRate =
        profile.hourlyRate ?? Money.zero(Currency.accountingCurrency);
    final hourlyEarnings = hourlyRate.scaledBy(payableDuration.inSeconds, 3600);

    final now = _clock.now();
    final earnings = ShiftHourlyEarnings(
      id: _idGenerator.nextEarningsId(),
      shiftId: shiftId,
      courierId: shift.courierId,
      compensationProfileId: profile.id,
      compensationProfileVersion: profile.version,
      earningsStartAt: earningsStartAt,
      earningsEndAt: earningsEndAt,
      payableDuration: payableDuration,
      hourlyRate: hourlyRate,
      hourlyEarnings: hourlyEarnings,
      fixedShiftAllowance: profile.fixedShiftAllowance ??
          Money.zero(Currency.accountingCurrency),
      nightBonus: profile.nightBonus ?? Money.zero(Currency.accountingCurrency),
      holidayBonus:
          profile.holidayBonus ?? Money.zero(Currency.accountingCurrency),
      wasCutShortByFinalDeliveryArrival: finalDeliveryVerifiedArrivalAt != null,
      calculatedAt: now,
    );
    await _earningsRepository.append(earnings);

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${earnings.id}-audit',
      branchId: shift.branchId,
      actorStaffId: performedByStaffId,
      courierId: shift.courierId,
      shiftId: shiftId,
      type: CourierAuditEventType.shiftEarningsCalculated,
      description:
          'Shift hourly earnings calculated: ${hourlyEarnings.minorUnits} '
          'minor units over ${payableDuration.inMinutes} minutes',
      timestamp: now,
      correlationId: earnings.id,
    ));

    return earnings;
  }
}
