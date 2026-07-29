import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/money.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_compensation_profile_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/compensation/courier_compensation_profile.dart';
import '../../domain/compensation/custom_bonus_rule.dart';
import '../identity/courier_compensation_profile_id_generator.dart';

/// Creates a new, versioned [CourierCompensationProfile] for a courier —
/// "every courier may have different values," "never overwrite previous
/// profiles." [version] is always `(highest existing version for
/// [courierId]) + 1` (starting at 1) — this use case never updates or
/// replaces an earlier version; a rate change, including a scheduled
/// future raise, is always a brand-new record with a later
/// [CourierCompensationProfile.effectiveFrom].
class CreateCourierCompensationProfile {
  const CreateCourierCompensationProfile({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierCompensationProfileIdGenerator idGenerator,
    required CourierCompensationProfileRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierCompensationProfileIdGenerator _idGenerator;
  final CourierCompensationProfileRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<CourierCompensationProfile> call({
    required String courierId,
    required String branchId,
    required DateTime effectiveFrom,
    DateTime? effectiveUntil,
    Money? hourlyRate,
    Money? deliveryFeePerPackage,
    double freeDistanceKm = 0,
    Money? extraDistanceRatePerKm,
    Money? fixedShiftAllowance,
    Money? nightBonus,
    Money? holidayBonus,
    List<CustomBonusRule> customBonusRules = const [],
    required String performedByStaffId,
  }) async {
    if (freeDistanceKm < 0) {
      throw const InvalidCompensationConfigurationViolation(
        reason: 'freeDistanceKm must not be negative',
      );
    }
    if (effectiveUntil != null && !effectiveUntil.isAfter(effectiveFrom)) {
      throw const InvalidCompensationConfigurationViolation(
        reason: 'effectiveUntil must be strictly after effectiveFrom',
      );
    }
    for (final rate in [
      hourlyRate,
      deliveryFeePerPackage,
      extraDistanceRatePerKm,
      fixedShiftAllowance,
      nightBonus,
      holidayBonus,
    ]) {
      if (rate != null && rate.isNegative) {
        throw const InvalidCompensationConfigurationViolation(
          reason: 'compensation rates must not be negative',
        );
      }
    }

    const action = PosAuthorizedAction.manageCourierCompensationProfile;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'courierId': courierId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existingVersions = await _repository.findAllByCourierId(courierId);
    final nextVersion = existingVersions.isEmpty
        ? 1
        : existingVersions
                .map((p) => p.version)
                .reduce((a, b) => a > b ? a : b) +
            1;

    final now = _clock.now();
    final profile = CourierCompensationProfile(
      id: _idGenerator.nextProfileId(),
      courierId: courierId,
      version: nextVersion,
      effectiveFrom: effectiveFrom,
      effectiveUntil: effectiveUntil,
      hourlyRate: hourlyRate,
      deliveryFeePerPackage: deliveryFeePerPackage,
      freeDistanceKm: freeDistanceKm,
      extraDistanceRatePerKm: extraDistanceRatePerKm,
      fixedShiftAllowance: fixedShiftAllowance,
      nightBonus: nightBonus,
      holidayBonus: holidayBonus,
      customBonusRules: customBonusRules,
      createdByStaffId: performedByStaffId,
      createdAt: now,
    );
    await _repository.append(profile);

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${profile.id}-audit',
      branchId: branchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      type: CourierAuditEventType.compensationProfileCreated,
      description:
          'Compensation profile v$nextVersion created, effective $effectiveFrom',
      timestamp: now,
      correlationId: profile.id,
    ));

    return profile;
  }
}
