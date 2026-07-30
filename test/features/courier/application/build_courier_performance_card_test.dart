import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_earnings_summary.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_performance_card.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_performance_snapshot.dart';
import 'package:abakus_one_v2/features/courier/data/courier_earnings_adjustment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_earnings_payment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/customer_contact_action_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_assignment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_earnings_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_failure_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/data/geofence_override_repository.dart';
import 'package:abakus_one_v2/features/courier/data/shift_hourly_earnings_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_failure.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_failure_reason.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/delivery_earnings.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/courier_test_fixtures.dart';

void main() {
  group('BuildCourierPerformanceCard', () {
    test(
        'composes the existing performance snapshot and earnings summary '
        'builders for the same period', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
        id: 'delivery-1',
        courierId: 'courier-1',
        status: DeliveryStatus.delivered,
      ));

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
        calculatedAt: DateTime(2026, 1, 1, 13),
      ));

      final failureRepository = InMemoryDeliveryFailureRepository();
      await failureRepository.append(DeliveryFailure(
        id: 'failure-1',
        deliveryId: 'delivery-1',
        reasonCode: DeliveryFailureReason.customerUnavailable,
        courierNote: 'Müşteriye ulaşılamadı.',
        recordedByStaffId: 'staff-1',
        recordedAt: DateTime(2026, 1, 1, 14),
      ));

      final useCase = BuildCourierPerformanceCard(
        buildPerformanceSnapshot: BuildCourierPerformanceSnapshot(
          deliveryRepository: deliveryRepository,
          assignmentRepository: InMemoryDeliveryAssignmentRepository(),
          failureRepository: failureRepository,
          geofenceOverrideRepository: InMemoryGeofenceOverrideRepository(),
          contactActionRepository: InMemoryCustomerContactActionRepository(),
        ),
        buildEarningsSummary: BuildCourierEarningsSummary(
          deliveryEarningsRepository: deliveryEarningsRepository,
          shiftEarningsRepository: InMemoryShiftHourlyEarningsRepository(),
          adjustmentRepository: InMemoryCourierEarningsAdjustmentRepository(),
          paymentRepository: InMemoryCourierEarningsPaymentRepository(),
        ),
      );

      final card = await useCase(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 2),
      );

      expect(card.courierId, 'courier-1');
      expect(card.performance.successfulDeliveries, 1);
      expect(card.earnings.packagesDelivered, 1);
      expect(
          card.earnings.packageEarnings, Money.fromWhole(20, Currency.tryLira));
      expect(card.cancelledDeliveries, 1);
    });

    test('zero activity in the period yields a zeroed, never-null card',
        () async {
      final useCase = BuildCourierPerformanceCard(
        buildPerformanceSnapshot: BuildCourierPerformanceSnapshot(
          deliveryRepository: InMemoryDeliveryRepository(),
          assignmentRepository: InMemoryDeliveryAssignmentRepository(),
          failureRepository: InMemoryDeliveryFailureRepository(),
          geofenceOverrideRepository: InMemoryGeofenceOverrideRepository(),
          contactActionRepository: InMemoryCustomerContactActionRepository(),
        ),
        buildEarningsSummary: BuildCourierEarningsSummary(
          deliveryEarningsRepository: InMemoryDeliveryEarningsRepository(),
          shiftEarningsRepository: InMemoryShiftHourlyEarningsRepository(),
          adjustmentRepository: InMemoryCourierEarningsAdjustmentRepository(),
          paymentRepository: InMemoryCourierEarningsPaymentRepository(),
        ),
      );

      final card = await useCase(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 2),
      );

      expect(card.performance.successfulDeliveries, 0);
      expect(card.cancelledDeliveries, 0);
      expect(card.earnings.grossEarnings, Money.zero(Currency.tryLira));
    });
  });
}
