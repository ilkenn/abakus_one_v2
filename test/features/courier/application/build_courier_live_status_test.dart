import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_live_status.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_live_status_for_branch.dart';
import 'package:abakus_one_v2/features/courier/data/courier_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/availability/courier_availability_status.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/courier/domain/events/courier_connection_monitor.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:abakus_one_v2/features/courier/domain/location/movement_state.dart';
import 'package:abakus_one_v2/features/courier/domain/location/signal_quality.dart';
import 'package:abakus_one_v2/features/courier/domain/device/courier_device.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../test_support/courier_test_fixtures.dart';

/// A minimal, canned [CourierConnectionMonitor] — real device/session
/// wiring is `InMemoryCourierConnectionMonitor`'s own concern (already
/// tested elsewhere); this fake only needs to answer `isStale`.
class _FakeConnectionMonitor implements CourierConnectionMonitor {
  _FakeConnectionMonitor({required this.stale});
  final bool stale;

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
      stale;

  @override
  Future<List<CourierDevice>> findStaleDevices({
    required String branchId,
    required Duration staleAfter,
    required DateTime now,
  }) async =>
      const [];
}

CourierLocationSnapshot _snapshot({
  double accuracyMeters = 10,
  double? speedMetersPerSecond,
  int? batteryLevelPercent,
}) {
  return CourierLocationSnapshot(
    id: 'loc-1',
    courierId: 'courier-1',
    deviceId: 'device-1',
    latitude: 41.0,
    longitude: 29.0,
    accuracyMeters: accuracyMeters,
    speedMetersPerSecond: speedMetersPerSecond,
    batteryLevelPercent: batteryLevelPercent,
    capturedAt: DateTime(2026, 1, 1, 12),
    receivedAt: DateTime(2026, 1, 1, 12),
  );
}

void main() {
  group('BuildCourierLiveStatus', () {
    late CourierLocationRepository locationRepository;
    late CourierAvailabilityRepository availabilityRepository;
    late CourierLocationAvailabilityRepository locationAvailabilityRepository;
    late DeliveryRepository deliveryRepository;

    setUp(() {
      locationRepository = InMemoryCourierLocationRepository();
      availabilityRepository = InMemoryCourierAvailabilityRepository();
      locationAvailabilityRepository =
          InMemoryCourierLocationAvailabilityRepository();
      deliveryRepository = InMemoryDeliveryRepository();
    });

    BuildCourierLiveStatus buildUseCase({required bool stale}) {
      return BuildCourierLiveStatus(
        clock: FakeClock(DateTime(2026, 1, 1, 12, 1)),
        locationRepository: locationRepository,
        connectionMonitor: _FakeConnectionMonitor(stale: stale),
        availabilityRepository: availabilityRepository,
        locationAvailabilityRepository: locationAvailabilityRepository,
        deliveryRepository: deliveryRepository,
      );
    }

    test('no location reading on record at all is offline with null fields',
        () async {
      final status = await buildUseCase(stale: true)(
        courierId: 'courier-1',
        branchId: 'branch-1',
      );

      expect(status.isOnline, isFalse);
      expect(status.hasNeverReportedLocation, isTrue);
      expect(status.availabilityStatus, CourierAvailabilityStatus.offline);
      expect(status.signalQuality, isNull);
      expect(status.movementState, isNull);
    });

    test(
        'a fresh reading with a not-stale connection is online, with '
        'derived signal quality and movement state', () async {
      await locationRepository.append(
        _snapshot(accuracyMeters: 10, speedMetersPerSecond: 8.0),
      );
      await availabilityRepository.save(buildTestAvailability(
        status: CourierAvailabilityStatus.busy,
      ));

      final status = await buildUseCase(stale: false)(
        courierId: 'courier-1',
        branchId: 'branch-1',
      );

      expect(status.isOnline, isTrue);
      expect(status.hasNeverReportedLocation, isFalse);
      expect(status.signalQuality, SignalQuality.good);
      expect(status.movementState, MovementState.vehicle);
      expect(status.availabilityStatus, CourierAvailabilityStatus.busy);
    });

    test(
        'a stale connection is offline even with a location reading on '
        'record', () async {
      await locationRepository.append(_snapshot());

      final status = await buildUseCase(stale: true)(
        courierId: 'courier-1',
        branchId: 'branch-1',
      );

      expect(status.isOnline, isFalse);
      expect(status.hasNeverReportedLocation, isFalse);
    });

    test('battery level flows through from the location snapshot', () async {
      await locationRepository.append(_snapshot(batteryLevelPercent: 42));

      final status = await buildUseCase(stale: false)(
        courierId: 'courier-1',
        branchId: 'branch-1',
      );

      expect(status.batteryLevelPercent, 42);
    });

    test('an active delivery is reflected on the status', () async {
      await deliveryRepository.save(buildTestDelivery(
        id: 'delivery-1',
        courierId: 'courier-1',
        status: DeliveryStatus.assigned,
      ));

      final status = await buildUseCase(stale: false)(
        courierId: 'courier-1',
        branchId: 'branch-1',
      );

      expect(status.activeDeliveryId, 'delivery-1');
    });
  });

  group('BuildCourierLiveStatusForBranch', () {
    test('builds a status for every courier eligible for the branch', () async {
      final courierRepository = InMemoryCourierRepository();
      await courierRepository.save(buildTestCourier(
        id: 'courier-1',
        primaryBranchId: 'branch-1',
      ));
      await courierRepository.save(buildTestCourier(
        id: 'courier-2',
        primaryBranchId: 'branch-1',
      ));
      await courierRepository.save(buildTestCourier(
        id: 'courier-3',
        primaryBranchId: 'branch-2',
      ));

      final buildForBranch = BuildCourierLiveStatusForBranch(
        courierRepository: courierRepository,
        buildCourierLiveStatus: BuildCourierLiveStatus(
          clock: FakeClock(DateTime(2026, 1, 1, 12)),
          locationRepository: InMemoryCourierLocationRepository(),
          connectionMonitor: _FakeConnectionMonitor(stale: true),
          availabilityRepository: InMemoryCourierAvailabilityRepository(),
          locationAvailabilityRepository:
              InMemoryCourierLocationAvailabilityRepository(),
          deliveryRepository: InMemoryDeliveryRepository(),
        ),
      );

      final statuses = await buildForBranch(branchId: 'branch-1');

      expect(
          statuses.map((s) => s.courierId).toSet(), {'courier-1', 'courier-2'});
    });
  });
}
