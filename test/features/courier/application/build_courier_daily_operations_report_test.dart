import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_daily_operations_report.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_performance_snapshot.dart';
import 'package:abakus_one_v2/features/courier/data/courier_repository.dart';
import 'package:abakus_one_v2/features/courier/data/customer_contact_action_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_assignment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_earnings_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_failure_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/data/geofence_override_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/delivery_earnings.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/courier_test_fixtures.dart';

void main() {
  group('BuildCourierDailyOperationsReport', () {
    BuildCourierDailyOperationsReport buildUseCase({
      required CourierRepository courierRepository,
      required DeliveryRepository deliveryRepository,
      required DeliveryEarningsRepository deliveryEarningsRepository,
    }) {
      return BuildCourierDailyOperationsReport(
        courierRepository: courierRepository,
        deliveryRepository: deliveryRepository,
        deliveryEarningsRepository: deliveryEarningsRepository,
        buildCourierPerformanceSnapshot: BuildCourierPerformanceSnapshot(
          deliveryRepository: deliveryRepository,
          assignmentRepository: InMemoryDeliveryAssignmentRepository(),
          failureRepository: InMemoryDeliveryFailureRepository(),
          geofenceOverrideRepository: InMemoryGeofenceOverrideRepository(),
          contactActionRepository: InMemoryCustomerContactActionRepository(),
        ),
      );
    }

    test(
        'only counts delivered deliveries with a deliveredAt inside the '
        'requested day', () async {
      final courierRepository = InMemoryCourierRepository();
      await courierRepository.save(buildTestCourier(id: 'courier-1'));

      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(Delivery(
        id: 'delivery-in-day',
        orderId: OrderId('order-1'),
        branchId: 'branch-1',
        status: DeliveryStatus.delivered,
        courierId: 'courier-1',
        createdAt: DateTime(2026, 1, 1, 12),
        deliveredAt: DateTime(2026, 1, 1, 12, 30),
        revision: 1,
      ));
      await deliveryRepository.save(Delivery(
        id: 'delivery-other-day',
        orderId: OrderId('order-2'),
        branchId: 'branch-1',
        status: DeliveryStatus.delivered,
        courierId: 'courier-1',
        createdAt: DateTime(2026, 1, 2, 12),
        deliveredAt: DateTime(2026, 1, 2, 12, 15),
        revision: 1,
      ));
      await deliveryRepository.save(Delivery(
        id: 'delivery-not-delivered',
        orderId: OrderId('order-3'),
        branchId: 'branch-1',
        status: DeliveryStatus.assigned,
        courierId: 'courier-1',
        createdAt: DateTime(2026, 1, 1, 13),
        revision: 1,
      ));

      final useCase = buildUseCase(
        courierRepository: courierRepository,
        deliveryRepository: deliveryRepository,
        deliveryEarningsRepository: InMemoryDeliveryEarningsRepository(),
      );

      final report = await useCase(
        branchId: 'branch-1',
        date: DateTime(2026, 1, 1, 8),
      );

      expect(report.totalDeliveries, 1);
      expect(report.averageDeliveryDurationSeconds, 1800);
      expect(report.peakHour, 12);
    });

    test('sums delivery-earnings distance across every branch courier',
        () async {
      final courierRepository = InMemoryCourierRepository();
      await courierRepository.save(buildTestCourier(id: 'courier-1'));
      await courierRepository.save(buildTestCourier(id: 'courier-2'));

      final deliveryEarningsRepository = InMemoryDeliveryEarningsRepository();
      await deliveryEarningsRepository.append(DeliveryEarnings(
        id: 'de-1',
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        orderId: OrderId('order-1'),
        compensationProfileId: 'profile-1',
        compensationProfileVersion: 1,
        packageFee: Money.fromWhole(20, Currency.tryLira),
        distanceKm: 4,
        freeDistanceKm: 3,
        extraDistanceKm: 1,
        extraDistanceEarnings: Money.zero(Currency.tryLira),
        totalEarnings: Money.fromWhole(20, Currency.tryLira),
        calculatedAt: DateTime(2026, 1, 1, 13),
      ));
      await deliveryEarningsRepository.append(DeliveryEarnings(
        id: 'de-2',
        deliveryId: 'delivery-2',
        courierId: 'courier-2',
        orderId: OrderId('order-2'),
        compensationProfileId: 'profile-1',
        compensationProfileVersion: 1,
        packageFee: Money.fromWhole(20, Currency.tryLira),
        distanceKm: 6,
        freeDistanceKm: 3,
        extraDistanceKm: 3,
        extraDistanceEarnings: Money.zero(Currency.tryLira),
        totalEarnings: Money.fromWhole(20, Currency.tryLira),
        calculatedAt: DateTime(2026, 1, 1, 14),
      ));

      final useCase = buildUseCase(
        courierRepository: courierRepository,
        deliveryRepository: InMemoryDeliveryRepository(),
        deliveryEarningsRepository: deliveryEarningsRepository,
      );

      final report = await useCase(
        branchId: 'branch-1',
        date: DateTime(2026, 1, 1),
      );

      expect(report.totalDistanceTravelledKm, 10);
      expect(report.courierPerformance, hasLength(2));
    });

    test('a day with no activity yields a zero report, never a crash',
        () async {
      final useCase = buildUseCase(
        courierRepository: InMemoryCourierRepository(),
        deliveryRepository: InMemoryDeliveryRepository(),
        deliveryEarningsRepository: InMemoryDeliveryEarningsRepository(),
      );

      final report = await useCase(
        branchId: 'branch-1',
        date: DateTime(2026, 1, 1),
      );

      expect(report.totalDeliveries, 0);
      expect(report.totalDistanceTravelledKm, 0);
      expect(report.averageDeliveryDurationSeconds, isNull);
      expect(report.peakHour, isNull);
      expect(report.courierPerformance, isEmpty);
    });
  });
}
