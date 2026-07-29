import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_earnings_summary.dart';
import 'package:abakus_one_v2/features/courier/data/courier_earnings_adjustment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_earnings_payment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_earnings_repository.dart';
import 'package:abakus_one_v2/features/courier/data/shift_hourly_earnings_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/delivery_earnings.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuildCourierEarningsSummary', () {
    test(
        'wires the repositories to the pure builder and only includes '
        'records within the requested period', () async {
      final deliveryEarningsRepository = InMemoryDeliveryEarningsRepository();
      await deliveryEarningsRepository.append(DeliveryEarnings(
        id: 'de-1',
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        orderId: OrderId('order-1'),
        compensationProfileId: 'profile-1',
        compensationProfileVersion: 1,
        packageFee: Money.fromWhole(20, Currency.tryLira),
        distanceKm: 2,
        freeDistanceKm: 3,
        extraDistanceKm: 0,
        extraDistanceEarnings: Money.zero(Currency.tryLira),
        totalEarnings: Money.fromWhole(20, Currency.tryLira),
        calculatedAt: DateTime(2026, 1, 15),
      ));
      await deliveryEarningsRepository.append(DeliveryEarnings(
        id: 'de-2',
        deliveryId: 'delivery-2',
        courierId: 'courier-1',
        orderId: OrderId('order-2'),
        compensationProfileId: 'profile-1',
        compensationProfileVersion: 1,
        packageFee: Money.fromWhole(20, Currency.tryLira),
        distanceKm: 2,
        freeDistanceKm: 3,
        extraDistanceKm: 0,
        extraDistanceEarnings: Money.zero(Currency.tryLira),
        totalEarnings: Money.fromWhole(20, Currency.tryLira),
        calculatedAt: DateTime(2026, 3, 15), // outside the queried period
      ));

      final useCase = BuildCourierEarningsSummary(
        deliveryEarningsRepository: deliveryEarningsRepository,
        shiftEarningsRepository: InMemoryShiftHourlyEarningsRepository(),
        adjustmentRepository: InMemoryCourierEarningsAdjustmentRepository(),
        paymentRepository: InMemoryCourierEarningsPaymentRepository(),
      );
      final summary = await useCase(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 2, 1),
      );
      expect(summary.packagesDelivered, 1);
      expect(summary.packageEarnings, Money.fromWhole(20, Currency.tryLira));
    });
  });
}
