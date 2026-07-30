import 'package:abakus_one_v2/features/courier/application/use_cases/sync_queued_courier_locations.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_repository.dart';
import 'package:abakus_one_v2/features/courier/data/offline_location_queue_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:abakus_one_v2/features/courier/domain/location/queued_location_sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../test_support/courier_test_fixtures.dart';

CourierLocationSnapshot _snapshot({
  required String id,
  required DateTime capturedAt,
  String deliveryId = 'delivery-1',
}) {
  return CourierLocationSnapshot(
    id: id,
    courierId: 'courier-1',
    deviceId: 'device-1',
    deliveryId: deliveryId,
    latitude: 41.0,
    longitude: 29.0,
    accuracyMeters: 10,
    capturedAt: capturedAt,
    receivedAt: capturedAt,
  );
}

void main() {
  group('SyncQueuedCourierLocations', () {
    late OfflineLocationQueueRepository queueRepository;
    late CourierLocationRepository locationRepository;
    late SyncQueuedCourierLocations useCase;

    setUp(() {
      queueRepository = InMemoryOfflineLocationQueueRepository();
      locationRepository = InMemoryCourierLocationRepository();
      useCase = SyncQueuedCourierLocations(
        clock: FakeClock(DateTime(2026, 1, 1, 13)),
        queueRepository: queueRepository,
        locationRepository: locationRepository,
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
    });

    test('replays every pending snapshot in capture order, oldest first',
        () async {
      await queueRepository.enqueue(
        _snapshot(id: 'loc-2', capturedAt: DateTime(2026, 1, 1, 12, 5)),
      );
      await queueRepository.enqueue(
        _snapshot(id: 'loc-1', capturedAt: DateTime(2026, 1, 1, 12, 0)),
      );

      final results = await useCase(deviceId: 'device-1', branchId: 'branch-1');

      expect(results.map((r) => r.snapshot.id).toList(), ['loc-1', 'loc-2']);
      expect(results.every((r) => r.status == QueuedLocationSyncStatus.synced),
          isTrue);
      expect(await locationRepository.containsId('loc-1'), isTrue);
      expect(await locationRepository.containsId('loc-2'), isTrue);
    });

    test(
        'a snapshot already recorded (e.g. a crash between append and '
        'markSynced) is never appended twice on retry', () async {
      final snapshot =
          _snapshot(id: 'loc-1', capturedAt: DateTime(2026, 1, 1, 12));
      await locationRepository.append(snapshot);
      await queueRepository.enqueue(snapshot);

      await useCase(deviceId: 'device-1', branchId: 'branch-1');

      final history = await locationRepository.findByDeliveryId('delivery-1');
      expect(history, hasLength(1));
    });

    test(
        'marks the queue entry synced even when the snapshot was already '
        'present', () async {
      final snapshot =
          _snapshot(id: 'loc-1', capturedAt: DateTime(2026, 1, 1, 12));
      await locationRepository.append(snapshot);
      await queueRepository.enqueue(snapshot);

      final results = await useCase(deviceId: 'device-1', branchId: 'branch-1');

      expect(results.single.status, QueuedLocationSyncStatus.synced);
      expect(
        await queueRepository.findPendingByDeviceId('device-1'),
        isEmpty,
      );
    });

    test(
        'enqueueing the same snapshot id twice never creates a duplicate '
        'queue entry', () async {
      final snapshot =
          _snapshot(id: 'loc-1', capturedAt: DateTime(2026, 1, 1, 12));
      await queueRepository.enqueue(snapshot);
      await queueRepository.enqueue(snapshot);

      final results = await useCase(deviceId: 'device-1', branchId: 'branch-1');

      expect(results, hasLength(1));
    });

    test('no pending snapshots for the device returns an empty list', () async {
      final results = await useCase(deviceId: 'device-1', branchId: 'branch-1');
      expect(results, isEmpty);
    });

    test('a synced snapshot never reappears in a later sync pass', () async {
      final snapshot =
          _snapshot(id: 'loc-1', capturedAt: DateTime(2026, 1, 1, 12));
      await queueRepository.enqueue(snapshot);
      await useCase(deviceId: 'device-1', branchId: 'branch-1');

      final secondPass =
          await useCase(deviceId: 'device-1', branchId: 'branch-1');
      expect(secondPass, isEmpty);
    });
  });
}
