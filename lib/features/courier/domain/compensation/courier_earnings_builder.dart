import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import 'courier_earnings_adjustment.dart';
import 'courier_earnings_payment.dart';
import 'courier_earnings_summary.dart';
import 'delivery_earnings.dart';
import 'shift_hourly_earnings.dart';

/// Builds a [CourierEarningsSummary] from already-loaded, immutable
/// records — a pure function, no I/O, mirrors
/// `CourierPerformanceBuilder.build`'s exact shape.
abstract final class CourierEarningsBuilder {
  CourierEarningsBuilder._();

  static CourierEarningsSummary build({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
    List<DeliveryEarnings> deliveryEarnings = const [],
    List<ShiftHourlyEarnings> shiftEarnings = const [],
    List<CourierEarningsAdjustment> adjustments = const [],
    List<CourierEarningsPayment> payments = const [],
  }) {
    final zero = Money.zero(Currency.accountingCurrency);

    final packageEarnings =
        deliveryEarnings.fold<Money>(zero, (sum, d) => sum + d.packageFee);
    final extraDistanceEarnings = deliveryEarnings.fold<Money>(
        zero, (sum, d) => sum + d.extraDistanceEarnings);
    final distanceTravelledKm =
        deliveryEarnings.fold<double>(0, (sum, d) => sum + d.distanceKm);
    final chargeableExtraDistanceKm =
        deliveryEarnings.fold<double>(0, (sum, d) => sum + d.extraDistanceKm);

    final hourlyEarnings =
        shiftEarnings.fold<Money>(zero, (sum, s) => sum + s.hourlyEarnings);
    final bonuses = shiftEarnings.fold<Money>(
        zero,
        (sum, s) =>
            sum + s.fixedShiftAllowance + s.nightBonus + s.holidayBonus);
    final hoursWorked = shiftEarnings.fold<Duration>(
        Duration.zero, (sum, s) => sum + s.payableDuration);

    final adjustmentsTotal =
        adjustments.fold<Money>(zero, (sum, a) => sum + a.amount);

    final grossEarnings = packageEarnings +
        hourlyEarnings +
        extraDistanceEarnings +
        bonuses +
        adjustmentsTotal;

    final paidAmount =
        payments.fold<Money>(zero, (sum, p) => sum + p.totalAmount);
    final pendingRaw = grossEarnings - paidAmount;
    final pendingAmount = pendingRaw.isNegative ? zero : pendingRaw;

    final packageCount = deliveryEarnings.length;
    final perDeliveryHourlyShare = packageCount == 0
        ? zero
        : Money(
            hourlyEarnings.minorUnits ~/ packageCount, hourlyEarnings.currency);

    final lineItems = deliveryEarnings
        .map((d) => DeliveryEarningsLineItem(
              deliveryId: d.deliveryId,
              orderReference: d.orderId.value,
              packageEarnings: d.packageFee,
              hourlyContribution: perDeliveryHourlyShare,
              extraDistanceEarnings: d.extraDistanceEarnings,
              bonuses: zero,
              totalEarnings: d.totalEarnings,
            ))
        .toList();

    return CourierEarningsSummary(
      courierId: courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      hoursWorked: hoursWorked,
      packagesDelivered: packageCount,
      distanceTravelledKm: distanceTravelledKm,
      chargeableExtraDistanceKm: chargeableExtraDistanceKm,
      packageEarnings: packageEarnings,
      hourlyEarnings: hourlyEarnings,
      extraDistanceEarnings: extraDistanceEarnings,
      bonuses: bonuses,
      adjustmentsTotal: adjustmentsTotal,
      grossEarnings: grossEarnings,
      paidAmount: paidAmount,
      pendingAmount: pendingAmount,
      deliveryLineItems: lineItems,
    );
  }
}
