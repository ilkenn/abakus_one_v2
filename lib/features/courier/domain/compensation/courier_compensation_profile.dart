import '../../../../shared/models/money.dart';
import 'custom_bonus_rule.dart';

/// One versioned, immutable compensation rate set for a courier — **never
/// overwritten**: a rate change always creates a brand-new profile with
/// [version] incremented, never a mutation of an earlier one
/// (`CourierCompensationProfileRepository` has no update method).
/// Historical earnings always resolve the profile that was
/// [coversAt] the moment being calculated, never the courier's *current*
/// rates — see `ShiftEarningsWindowCalculator`/`CalculateDeliveryEarnings`.
///
/// Deliberately separate from `CourierCompensationMetadata`
/// (`courier_compensation_metadata.dart`, Phase 5's original inert
/// `hourlyRate`/`perPackageRate`-only placeholder embedded in
/// `CourierOperationalProfile`) — that type has no versioning/effective-
/// date support and is left completely untouched by this sprint (see
/// `docs/decisions.md` ADR-018 for why a new type was introduced instead
/// of retrofitting versioning onto it).
class CourierCompensationProfile {
  const CourierCompensationProfile({
    required this.id,
    required this.courierId,
    required this.version,
    required this.effectiveFrom,
    this.effectiveUntil,
    this.isActive = true,
    this.hourlyRate,
    this.deliveryFeePerPackage,
    this.freeDistanceKm = 0,
    this.extraDistanceRatePerKm,
    this.fixedShiftAllowance,
    this.nightBonus,
    this.holidayBonus,
    this.customBonusRules = const [],
    required this.createdByStaffId,
    required this.createdAt,
  });

  final String id;
  final String courierId;

  /// 1-based, strictly increasing per courier — never reused, never
  /// decremented.
  final int version;

  final DateTime effectiveFrom;

  /// `null` means open-ended — the current/latest profile for this
  /// courier, until a manager schedules a future one (which implicitly
  /// bounds this one by creating the next version with its own
  /// [effectiveFrom]; this profile's own [effectiveUntil] is still left
  /// `null` — "covers" resolution always picks the highest [version] whose
  /// range contains the queried instant, never relies on a closed
  /// [effectiveUntil] being back-filled).
  final DateTime? effectiveUntil;

  /// A manager may deactivate a mistakenly-scheduled future version
  /// without deleting it — `coversAt` never matches an inactive profile.
  final bool isActive;

  final Money? hourlyRate;
  final Money? deliveryFeePerPackage;

  /// Kilometers of every delivery's distance that are never chargeable —
  /// manager-configured per courier, any non-negative value (0 included).
  final double freeDistanceKm;

  final Money? extraDistanceRatePerKm;
  final Money? fixedShiftAllowance;
  final Money? nightBonus;
  final Money? holidayBonus;
  final List<CustomBonusRule> customBonusRules;

  final String createdByStaffId;
  final DateTime createdAt;

  /// Whether this profile is the one that applied at instant [at] — active
  /// and within `[effectiveFrom, effectiveUntil)`.
  bool coversAt(DateTime at) {
    if (!isActive) return false;
    if (at.isBefore(effectiveFrom)) return false;
    final until = effectiveUntil;
    if (until != null && !at.isBefore(until)) return false;
    return true;
  }
}
