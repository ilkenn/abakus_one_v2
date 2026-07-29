import 'package:abakus_one_v2/features/courier/domain/compensation/courier_earnings_adjustment.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/courier_earnings_adjustment_reason.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/courier_earnings_builder.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/courier_earnings_payment.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/delivery_earnings.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/shift_hourly_earnings.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

Money _try(int whole) => Money.fromWhole(whole, Currency.tryLira);

DeliveryEarnings _deliveryEarnings({
  String id = 'de-1',
  Money? packageFee,
  Money? extraDistanceEarnings,
  double distanceKm = 5,
  double extraDistanceKm = 2,
}) {
  return DeliveryEarnings(
    id: id,
    deliveryId: 'delivery-1',
    courierId: 'courier-1',
    orderId: OrderId('order-1'),
    compensationProfileId: 'profile-1',
    compensationProfileVersion: 1,
    packageFee: packageFee ?? _try(20),
    distanceKm: distanceKm,
    freeDistanceKm: 3,
    extraDistanceKm: extraDistanceKm,
    extraDistanceEarnings: extraDistanceEarnings ?? _try(5),
    totalEarnings:
        (packageFee ?? _try(20)) + (extraDistanceEarnings ?? _try(5)),
    calculatedAt: DateTime(2026, 1, 1),
  );
}

ShiftHourlyEarnings _shiftEarnings({
  String id = 'se-1',
  Money? hourlyEarnings,
  Duration payableDuration = const Duration(hours: 8),
}) {
  return ShiftHourlyEarnings(
    id: id,
    shiftId: 'shift-1',
    courierId: 'courier-1',
    compensationProfileId: 'profile-1',
    compensationProfileVersion: 1,
    earningsStartAt: DateTime(2026, 1, 1, 10),
    earningsEndAt: DateTime(2026, 1, 1, 18),
    payableDuration: payableDuration,
    hourlyRate: _try(10),
    hourlyEarnings: hourlyEarnings ?? _try(80),
    fixedShiftAllowance: _try(15),
    nightBonus: Money.zero(Currency.tryLira),
    holidayBonus: Money.zero(Currency.tryLira),
    calculatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('CourierEarningsBuilder', () {
    test('aggregates package/extra-distance/hourly/bonus totals correctly', () {
      final summary = CourierEarningsBuilder.build(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 2, 1),
        deliveryEarnings: [_deliveryEarnings(), _deliveryEarnings(id: 'de-2')],
        shiftEarnings: [_shiftEarnings()],
      );
      expect(summary.packageEarnings, _try(40));
      expect(summary.extraDistanceEarnings, _try(10));
      expect(summary.hourlyEarnings, _try(80));
      expect(summary.bonuses, _try(15));
      expect(summary.packagesDelivered, 2);
      expect(summary.hoursWorked, const Duration(hours: 8));
    });

    test('grossEarnings sums every component including signed adjustments', () {
      final summary = CourierEarningsBuilder.build(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 2, 1),
        deliveryEarnings: [_deliveryEarnings()],
        shiftEarnings: [_shiftEarnings()],
        adjustments: [
          CourierEarningsAdjustment(
            id: 'adj-1',
            courierId: 'courier-1',
            reason: CourierEarningsAdjustmentReason.manualCorrection,
            amount: -_try(10),
            actorStaffId: 'manager-1',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      // package 20 + extraDistance 5 + hourly 80 + bonus 15 - adjustment 10
      expect(summary.grossEarnings, _try(110));
      expect(summary.adjustmentsTotal, -_try(10));
    });

    test('pendingAmount is grossEarnings minus paidAmount, floored at zero',
        () {
      final summaryWithNoPayment = CourierEarningsBuilder.build(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 2, 1),
        deliveryEarnings: [_deliveryEarnings()],
      );
      expect(summaryWithNoPayment.pendingAmount,
          summaryWithNoPayment.grossEarnings);

      final summaryFullyPaid = CourierEarningsBuilder.build(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 2, 1),
        deliveryEarnings: [_deliveryEarnings()],
        payments: [
          CourierEarningsPayment(
            id: 'pay-1',
            courierId: 'courier-1',
            periodStart: DateTime(2026, 1, 1),
            periodEnd: DateTime(2026, 2, 1),
            totalAmount: _try(1000),
            deliveryEarningsIds: const ['de-1'],
            shiftEarningsIds: const [],
            adjustmentIds: const [],
            paidByStaffId: 'manager-1',
            paidAt: DateTime(2026, 1, 2),
          ),
        ],
      );
      expect(summaryFullyPaid.pendingAmount.isZero, isTrue);
    });

    test(
        'deliveryLineItems mirror each DeliveryEarnings with an '
        'informational hourly-contribution share, never double-counted', () {
      final summary = CourierEarningsBuilder.build(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 2, 1),
        deliveryEarnings: [_deliveryEarnings(), _deliveryEarnings(id: 'de-2')],
        shiftEarnings: [_shiftEarnings()],
      );
      expect(summary.deliveryLineItems, hasLength(2));
      final sumOfContributions = summary.deliveryLineItems
          .map((i) => i.hourlyContribution.minorUnits)
          .reduce((a, b) => a + b);
      // Each of 2 deliveries gets an equal share of the 80 TRY hourly
      // earnings - the shares sum back to (approximately) the total.
      expect(sumOfContributions, summary.hourlyEarnings.minorUnits);
    });
  });
}
