import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_live_status.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_live_warnings.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_operation_health.dart';
import 'package:abakus_one_v2/features/courier/data/courier_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_fraud_signal_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/courier/domain/events/courier_connection_monitor.dart';
import 'package:abakus_one_v2/features/courier/domain/device/courier_device.dart';
import 'package:abakus_one_v2/features/courier/domain/health/courier_operation_health_level.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../test_support/courier_test_fixtures.dart';

class _FakeConnectionMonitor implements CourierConnectionMonitor {
  @override
  Future<void> recordHeartbeat({
    required String deviceId,
    required DateTime at,
  }) async {}

  @override
  Future<bool> isStale({
    required String deviceId,
    required Duration staleAfter,
    required DateTime now,
  }) async =>
      true;

  @override
  Future<List<CourierDevice>> findStaleDevices({
    required String branchId,
    required Duration staleAfter,
    required DateTime now,
  }) async =>
      const [];
}

void main() {
  final now = DateTime(2026, 1, 1, 12);

  group('BuildCourierOperationHealth', () {
    BuildCourierOperationHealth buildUseCase({
      required DeliveryRepository deliveryRepository,
      required CourierRepository courierRepository,
    }) {
      return BuildCourierOperationHealth(
        clock: FakeClock(now),
        deliveryRepository: deliveryRepository,
        buildCourierLiveWarnings: BuildCourierLiveWarnings(
          clock: FakeClock(now),
          courierRepository: courierRepository,
          buildCourierLiveStatus: BuildCourierLiveStatus(
            clock: FakeClock(now),
            locationRepository: InMemoryCourierLocationRepository(),
            connectionMonitor: _FakeConnectionMonitor(),
            availabilityRepository: InMemoryCourierAvailabilityRepository(),
            locationAvailabilityRepository:
                InMemoryCourierLocationAvailabilityRepository(),
            deliveryRepository: deliveryRepository,
          ),
          locationAvailabilityRepository:
              InMemoryCourierLocationAvailabilityRepository(),
          fraudSignalRepository: InMemoryCourierFraudSignalRepository(),
        ),
      );
    }

    test('an empty branch is healthy', () async {
      final useCase = buildUseCase(
        deliveryRepository: InMemoryDeliveryRepository(),
        courierRepository: InMemoryCourierRepository(),
      );

      final health = await useCase(branchId: 'branch-1');

      expect(health.level, CourierOperationHealthLevel.healthy);
      expect(health.delayedDeliveryCount, 0);
      expect(health.offlineCourierCount, 0);
    });

    test('an active delivery older than the delay threshold is degraded',
        () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(Delivery(
        id: 'delivery-1',
        orderId: OrderId('order-1'),
        branchId: 'branch-1',
        status: DeliveryStatus.assigned,
        courierId: 'courier-1',
        createdAt: now.subtract(const Duration(minutes: 30)),
        revision: 1,
      ));

      final useCase = BuildCourierOperationHealth(
        clock: FakeClock(now),
        deliveryRepository: deliveryRepository,
        buildCourierLiveWarnings: BuildCourierLiveWarnings(
          clock: FakeClock(now),
          courierRepository: InMemoryCourierRepository(),
          buildCourierLiveStatus: BuildCourierLiveStatus(
            clock: FakeClock(now),
            locationRepository: InMemoryCourierLocationRepository(),
            connectionMonitor: _FakeConnectionMonitor(),
            availabilityRepository: InMemoryCourierAvailabilityRepository(),
            locationAvailabilityRepository:
                InMemoryCourierLocationAvailabilityRepository(),
            deliveryRepository: deliveryRepository,
          ),
          locationAvailabilityRepository:
              InMemoryCourierLocationAvailabilityRepository(),
          fraudSignalRepository: InMemoryCourierFraudSignalRepository(),
        ),
        delayThreshold: const Duration(minutes: 5),
      );

      final health = await useCase(branchId: 'branch-1');

      expect(health.delayedDeliveryCount, 1);
      expect(health.level, CourierOperationHealthLevel.degraded);
    });

    test('five waiting deliveries cross the critical threshold', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      for (var i = 0; i < 5; i++) {
        await deliveryRepository.save(buildTestDelivery(
          id: 'delivery-$i',
          branchId: 'branch-1',
          status: DeliveryStatus.readyForAssignment,
        ));
      }

      final useCase = buildUseCase(
        deliveryRepository: deliveryRepository,
        courierRepository: InMemoryCourierRepository(),
      );

      final health = await useCase(branchId: 'branch-1');

      expect(health.waitingDeliveryCount, 5);
      expect(health.level, CourierOperationHealthLevel.critical);
    });

    test(
        'an offline courier is reflected via the reused live-warnings '
        'aggregator', () async {
      final courierRepository = InMemoryCourierRepository();
      await courierRepository.save(buildTestCourier(id: 'courier-1'));

      final useCase = buildUseCase(
        deliveryRepository: InMemoryDeliveryRepository(),
        courierRepository: courierRepository,
      );

      final health = await useCase(branchId: 'branch-1');

      expect(health.offlineCourierCount, 1);
      expect(health.level, CourierOperationHealthLevel.degraded);
    });
  });
}
