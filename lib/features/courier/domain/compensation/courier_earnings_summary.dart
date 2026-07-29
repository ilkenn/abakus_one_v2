import '../../../../shared/models/money.dart';

/// One delivery's earnings, broken down for the courier-facing dashboard —
/// "the courier must understand exactly why every amount exists." Purely
/// a display-friendly reshaping of an already-calculated [DeliveryEarnings]
/// plus an *informational* pro-rata share of the shift's hourly earnings;
/// [hourlyContribution] is never a separate financial record and is never
/// summed into [CourierEarningsSummary.grossEarnings] a second time (it is
/// already included via [CourierEarningsSummary.hourlyEarnings]).
class DeliveryEarningsLineItem {
  const DeliveryEarningsLineItem({
    required this.deliveryId,
    required this.orderReference,
    required this.packageEarnings,
    required this.hourlyContribution,
    required this.extraDistanceEarnings,
    required this.bonuses,
    required this.totalEarnings,
  });

  final String deliveryId;

  /// `Delivery.orderId.value` — the same identifier every other courier
  /// screen already displays (`ActiveDeliveryScreen`'s "Sipariş:" label),
  /// not a separate order-number lookup.
  final String orderReference;

  final Money packageEarnings;
  final Money hourlyContribution;
  final Money extraDistanceEarnings;
  final Money bonuses;
  final Money totalEarnings;
}

/// A computed, read-only earnings rollup for one courier over one period
/// — **never persisted as authoritative data**, always rebuildable from
/// the underlying immutable [DeliveryEarnings]/[ShiftHourlyEarnings]/
/// [CourierEarningsAdjustment]/[CourierEarningsPayment] records, mirroring
/// `CourierPerformanceSnapshot`'s exact same "computed, never stored"
/// discipline.
class CourierEarningsSummary {
  const CourierEarningsSummary({
    required this.courierId,
    required this.periodStart,
    required this.periodEnd,
    this.hoursWorked = Duration.zero,
    this.packagesDelivered = 0,
    this.distanceTravelledKm = 0,
    this.chargeableExtraDistanceKm = 0,
    required this.packageEarnings,
    required this.hourlyEarnings,
    required this.extraDistanceEarnings,
    required this.bonuses,
    required this.adjustmentsTotal,
    required this.grossEarnings,
    required this.paidAmount,
    required this.pendingAmount,
    this.deliveryLineItems = const [],
  });

  final String courierId;
  final DateTime periodStart;
  final DateTime periodEnd;

  final Duration hoursWorked;
  final int packagesDelivered;
  final double distanceTravelledKm;
  final double chargeableExtraDistanceKm;

  final Money packageEarnings;
  final Money hourlyEarnings;
  final Money extraDistanceEarnings;

  /// Sum of every `ShiftHourlyEarnings.fixedShiftAllowance` +
  /// `.nightBonus` + `.holidayBonus` in the period.
  final Money bonuses;

  /// Signed — the sum of every `CourierEarningsAdjustment.amount` in the
  /// period (a deduction lowers this below zero).
  final Money adjustmentsTotal;

  /// `packageEarnings + hourlyEarnings + extraDistanceEarnings + bonuses +
  /// adjustmentsTotal`.
  final Money grossEarnings;

  /// Sum of every `CourierEarningsPayment.totalAmount` in the period.
  final Money paidAmount;

  /// `grossEarnings - paidAmount`, floored at zero.
  final Money pendingAmount;

  final List<DeliveryEarningsLineItem> deliveryLineItems;
}
