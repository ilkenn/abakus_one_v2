import '../../../../shared/models/money.dart';

/// One immutable, computed-once hourly-earnings record for a single
/// [CourierShift] — mirrors [DeliveryEarnings]'s "computed once, no update
/// method, idempotent recompute returns the same record" shape.
///
/// [earningsStartAt]/[earningsEndAt] are the exact window
/// `ShiftEarningsWindowCalculator` determined — never the shift's raw
/// `startedAt`/`endedAt` directly (early arrival never creates extra
/// earnings; a final in-progress delivery may cut the window short of the
/// scheduled end, per [wasCutShortByFinalDeliveryArrival]).
class ShiftHourlyEarnings {
  const ShiftHourlyEarnings({
    required this.id,
    required this.shiftId,
    required this.courierId,
    required this.compensationProfileId,
    required this.compensationProfileVersion,
    required this.earningsStartAt,
    required this.earningsEndAt,
    required this.payableDuration,
    required this.hourlyRate,
    required this.hourlyEarnings,
    required this.fixedShiftAllowance,
    required this.nightBonus,
    required this.holidayBonus,
    this.wasCutShortByFinalDeliveryArrival = false,
    required this.calculatedAt,
  });

  final String id;
  final String shiftId;
  final String courierId;
  final String compensationProfileId;
  final int compensationProfileVersion;

  final DateTime earningsStartAt;
  final DateTime earningsEndAt;

  /// `earningsEndAt - earningsStartAt`, never negative (a shift that ends
  /// before its own computed start — e.g. a courier who never logged in —
  /// yields `Duration.zero`, not a negative duration).
  final Duration payableDuration;

  /// Snapshot of the profile's hourly rate at calculation time.
  final Money hourlyRate;

  /// `hourlyRate × (payableDuration in hours)`.
  final Money hourlyEarnings;

  final Money fixedShiftAllowance;
  final Money nightBonus;
  final Money holidayBonus;

  /// `true` when [earningsEndAt] came from the first verified customer-
  /// geofence arrival of an in-progress final delivery rather than the
  /// shift's own scheduled/actual end — "prevent intentional waiting
  /// outside the customer's door."
  final bool wasCutShortByFinalDeliveryArrival;

  final DateTime calculatedAt;
}
