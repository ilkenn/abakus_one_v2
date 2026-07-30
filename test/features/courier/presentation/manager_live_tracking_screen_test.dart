import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/device/courier_device.dart';
import 'package:abakus_one_v2/features/courier/domain/events/courier_connection_monitor.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:abakus_one_v2/features/courier/presentation/providers/courier_dependencies_provider.dart';
import 'package:abakus_one_v2/features/courier/presentation/screens/manager_live_tracking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      false;

  @override
  Future<List<CourierDevice>> findStaleDevices({
    required String branchId,
    required Duration staleAfter,
    required DateTime now,
  }) async =>
      const [];
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required CourierRepository courierRepository,
    CourierLocationRepository? locationRepository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 1, 1, 12))),
          courierRepositoryProvider.overrideWithValue(courierRepository),
          if (locationRepository != null)
            courierLocationRepositoryProvider
                .overrideWithValue(locationRepository),
          courierConnectionMonitorProvider
              .overrideWithValue(_FakeConnectionMonitor()),
        ],
        child: const MaterialApp(
          home: ManagerLiveTrackingScreen(branchId: 'branch-1'),
        ),
      ),
    );
  }

  testWidgets('shows a loading indicator before the first load completes',
      (tester) async {
    final courierRepository = InMemoryCourierRepository();
    await courierRepository.save(buildTestCourier(primaryBranchId: 'branch-1'));

    await pumpScreen(tester, courierRepository: courierRepository);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows an empty state when the branch has no couriers',
      (tester) async {
    await pumpScreen(
      tester,
      courierRepository: InMemoryCourierRepository(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bu şubede kayıtlı kurye bulunmuyor.'), findsOneWidget);
  });

  testWidgets(
      'shows one card per courier, distinguishing reported-location vs '
      'never-reported', (tester) async {
    final courierRepository = InMemoryCourierRepository();
    await courierRepository.save(buildTestCourier(
      id: 'courier-1',
      primaryBranchId: 'branch-1',
    ));
    await courierRepository.save(buildTestCourier(
      id: 'courier-2',
      primaryBranchId: 'branch-1',
    ));

    final locationRepository = InMemoryCourierLocationRepository();
    await locationRepository.append(CourierLocationSnapshot(
      id: 'loc-1',
      courierId: 'courier-1',
      deviceId: 'device-1',
      latitude: 41.0,
      longitude: 29.0,
      accuracyMeters: 10,
      capturedAt: DateTime(2026, 1, 1, 12),
      receivedAt: DateTime(2026, 1, 1, 12),
    ));

    await pumpScreen(
      tester,
      courierRepository: courierRepository,
      locationRepository: locationRepository,
    );
    await tester.pumpAndSettle();

    expect(find.text('courier-1'), findsOneWidget);
    expect(find.text('courier-2'), findsOneWidget);
    expect(find.text('Konum verisi yok'), findsOneWidget);
    expect(find.textContaining('41.00000'), findsOneWidget);
  });
}
