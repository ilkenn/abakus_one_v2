import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_live_status.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_live_warnings.dart';
import 'package:abakus_one_v2/features/courier/data/courier_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_fraud_signal_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/events/courier_connection_monitor.dart';
import 'package:abakus_one_v2/features/courier/domain/device/courier_device.dart';
import 'package:abakus_one_v2/features/courier/domain/fraud/courier_fraud_signal.dart';
import 'package:abakus_one_v2/features/courier/domain/fraud/courier_fraud_signal_type.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_availability.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:abakus_one_v2/features/courier/domain/location/location_unavailable_reason.dart';
import 'package:abakus_one_v2/features/courier/domain/warnings/courier_live_warning_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../test_support/courier_test_fixtures.dart';

/// A canned [CourierConnectionMonitor] — only `isStale` matters here.
class _FakeConnectionMonitor implements CourierConnectionMonitor {
  _FakeConnectionMonitor({this.stale = false});
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
  String courierId = 'courier-1',
  double speedMetersPerSecond = 2.0,
  required DateTime receivedAt,
}) {
  return CourierLocationSnapshot(
    id: 'loc-1',
    courierId: courierId,
    deviceId: 'device-1',
    latitude: 41.0,
    longitude: 29.0,
    accuracyMeters: 10,
    speedMetersPerSecond: speedMetersPerSecond,
    capturedAt: receivedAt,
    receivedAt: receivedAt,
  );
}

void main() {
  final now = DateTime(2026, 1, 1, 12);

  group('BuildCourierLiveWarnings', () {
    late CourierRepository courierRepository;
    late CourierLocationRepository locationRepository;
    late CourierAvailabilityRepository availabilityRepository;
    late CourierLocationAvailabilityRepository locationAvailabilityRepository;
    late DeliveryRepository deliveryRepository;
    late CourierFraudSignalRepository fraudSignalRepository;

    setUp(() {
      courierRepository = InMemoryCourierRepository();
      locationRepository = InMemoryCourierLocationRepository();
      availabilityRepository = InMemoryCourierAvailabilityRepository();
      locationAvailabilityRepository =
          InMemoryCourierLocationAvailabilityRepository();
      deliveryRepository = InMemoryDeliveryRepository();
      fraudSignalRepository = InMemoryCourierFraudSignalRepository();
    });

    BuildCourierLiveWarnings buildUseCase({bool connectionStale = false}) {
      return BuildCourierLiveWarnings(
        clock: FakeClock(now),
        courierRepository: courierRepository,
        buildCourierLiveStatus: BuildCourierLiveStatus(
          clock: FakeClock(now),
          locationRepository: locationRepository,
          connectionMonitor: _FakeConnectionMonitor(stale: connectionStale),
          availabilityRepository: availabilityRepository,
          locationAvailabilityRepository: locationAvailabilityRepository,
          deliveryRepository: deliveryRepository,
        ),
        locationAvailabilityRepository: locationAvailabilityRepository,
        fraudSignalRepository: fraudSignalRepository,
      );
    }

    test('no warnings for a healthy, online, recently-updated courier',
        () async {
      await courierRepository.save(buildTestCourier());
      await locationRepository
          .append(_snapshot(speedMetersPerSecond: 2.0, receivedAt: now));

      final warnings = await buildUseCase()(branchId: 'branch-1');

      expect(warnings, isEmpty);
    });

    test('offline courier (no location on record) triggers courierOffline',
        () async {
      await courierRepository.save(buildTestCourier());

      final warnings = await buildUseCase()(branchId: 'branch-1');

      expect(
        warnings.map((w) => w.type),
        contains(CourierLiveWarningType.courierOffline),
      );
    });

    test('a serviceDisabled location-availability reason triggers gpsDisabled',
        () async {
      await courierRepository.save(buildTestCourier());
      await locationRepository
          .append(_snapshot(speedMetersPerSecond: 2.0, receivedAt: now));
      await locationAvailabilityRepository.save(CourierLocationAvailability(
        courierId: 'courier-1',
        status: CourierLocationAvailabilityStatus.unavailable,
        reason: LocationUnavailableReason.serviceDisabled,
        updatedAt: now,
        revision: 1,
      ));

      final warnings = await buildUseCase()(branchId: 'branch-1');

      expect(
        warnings.map((w) => w.type),
        contains(CourierLiveWarningType.gpsDisabled),
      );
    });

    test(
        'a stale-but-present location reading triggers noLocationUpdates '
        'without also flagging courierOffline', () async {
      await courierRepository.save(buildTestCourier());
      await locationRepository.append(_snapshot(
        speedMetersPerSecond: 2.0,
        receivedAt: now.subtract(const Duration(minutes: 10)),
      ));

      final warnings = await buildUseCase(connectionStale: false)(
        branchId: 'branch-1',
      );

      final types = warnings.map((w) => w.type).toSet();
      expect(types, contains(CourierLiveWarningType.noLocationUpdates));
      expect(types, isNot(contains(CourierLiveWarningType.courierOffline)));
    });

    test('a stationary courier with an old reading triggers longInactivity',
        () async {
      await courierRepository.save(buildTestCourier());
      await locationRepository.append(_snapshot(
        speedMetersPerSecond: 0.0,
        receivedAt: now.subtract(const Duration(minutes: 20)),
      ));

      final warnings = await buildUseCase(connectionStale: false)(
        branchId: 'branch-1',
      );

      expect(
        warnings.map((w) => w.type),
        contains(CourierLiveWarningType.longInactivity),
      );
    });

    test('a recent gpsJump fraud signal triggers abnormalRoute', () async {
      await courierRepository.save(buildTestCourier());
      await locationRepository
          .append(_snapshot(speedMetersPerSecond: 2.0, receivedAt: now));
      await fraudSignalRepository.append(CourierFraudSignal(
        id: 'signal-1',
        courierId: 'courier-1',
        deviceId: 'device-1',
        type: CourierFraudSignalType.gpsJump,
        description: 'test signal',
        detectedAt: now,
      ));

      final warnings = await buildUseCase()(branchId: 'branch-1');

      expect(
        warnings.map((w) => w.type),
        contains(CourierLiveWarningType.abnormalRoute),
      );
    });

    test(
        'reaching the operational-risk signal threshold triggers '
        'operationalRisk', () async {
      await courierRepository.save(buildTestCourier());
      await locationRepository
          .append(_snapshot(speedMetersPerSecond: 2.0, receivedAt: now));
      for (var i = 0; i < 3; i++) {
        await fraudSignalRepository.append(CourierFraudSignal(
          id: 'signal-$i',
          courierId: 'courier-1',
          deviceId: 'device-1',
          type: CourierFraudSignalType.impossibleSpeed,
          description: 'test signal $i',
          detectedAt: now,
        ));
      }

      final warnings = await buildUseCase()(branchId: 'branch-1');

      expect(
        warnings.map((w) => w.type),
        contains(CourierLiveWarningType.operationalRisk),
      );
    });

    test('fraud signals outside the recent window are ignored', () async {
      await courierRepository.save(buildTestCourier());
      await locationRepository
          .append(_snapshot(speedMetersPerSecond: 2.0, receivedAt: now));
      await fraudSignalRepository.append(CourierFraudSignal(
        id: 'signal-1',
        courierId: 'courier-1',
        deviceId: 'device-1',
        type: CourierFraudSignalType.gpsJump,
        description: 'stale signal',
        detectedAt: now.subtract(const Duration(hours: 5)),
      ));

      final warnings = await buildUseCase()(branchId: 'branch-1');

      expect(
        warnings.map((w) => w.type),
        isNot(contains(CourierLiveWarningType.abnormalRoute)),
      );
    });

    test('only couriers eligible for the branch are considered', () async {
      await courierRepository.save(buildTestCourier(
        id: 'courier-1',
        primaryBranchId: 'branch-1',
      ));
      await courierRepository.save(buildTestCourier(
        id: 'courier-2',
        primaryBranchId: 'branch-2',
      ));
      await locationRepository
          .append(_snapshot(speedMetersPerSecond: 2.0, receivedAt: now));

      final warnings = await buildUseCase()(branchId: 'branch-1');

      expect(warnings.every((w) => w.courierId == 'courier-1'), isTrue);
    });
  });
}
