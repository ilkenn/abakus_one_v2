import '../../../../core/utils/clock.dart';
import '../../data/courier_location_repository.dart';
import '../../data/offline_location_queue_repository.dart';
import '../../domain/events/courier_event_type.dart';
import '../../domain/location/queued_courier_location.dart';
import '../../domain/location/queued_location_sync_status.dart';
import 'record_courier_event.dart';

/// Replays every still-pending [QueuedCourierLocation] for one device, in
/// capture order — Sprint 5B Part 7's "replay," "reconnect sync," and "no
/// location loss after temporary disconnect."
///
/// **A deliberate sibling of `RecordCourierLocationSnapshot`, not a reuse
/// of it**: that use case always mints a fresh id via its
/// `CourierLocationSnapshotIdGenerator`, which would turn every retried
/// sync into a brand-new duplicate reading — the opposite of
/// "deduplication." Here, each snapshot's id was already assigned once at
/// capture time (by whatever produced it before queuing — e.g.
/// `GeolocatorCourierLocationProvider`) and is preserved verbatim;
/// `CourierLocationRepository.containsId` is checked before every append,
/// so a sync that gets interrupted after the append but before
/// [OfflineLocationQueueRepository.markSynced] (a crash mid-sync) never
/// double-records on the next retry — it just marks the already-persisted
/// entry synced.
///
/// Event-recording reuses the exact same idempotency key format
/// (`'<snapshotId>-location'`) `RecordCourierLocationSnapshot` uses, so
/// `RecordCourierEvent`'s own idempotency guard covers this path too.
class SyncQueuedCourierLocations {
  const SyncQueuedCourierLocations({
    required Clock clock,
    required OfflineLocationQueueRepository queueRepository,
    required CourierLocationRepository locationRepository,
    required RecordCourierEvent recordCourierEvent,
  })  : _clock = clock,
        _queueRepository = queueRepository,
        _locationRepository = locationRepository,
        _recordCourierEvent = recordCourierEvent;

  final Clock _clock;
  final OfflineLocationQueueRepository _queueRepository;
  final CourierLocationRepository _locationRepository;
  final RecordCourierEvent _recordCourierEvent;

  Future<List<QueuedCourierLocation>> call({
    required String deviceId,
    required String branchId,
  }) async {
    final pending = await _queueRepository.findPendingByDeviceId(deviceId);
    final results = <QueuedCourierLocation>[];

    for (final queued in pending) {
      final snapshot = queued.snapshot;
      final now = _clock.now();

      if (!(await _locationRepository.containsId(snapshot.id))) {
        await _locationRepository.append(snapshot);
        await _recordCourierEvent(
          branchId: branchId,
          courierId: snapshot.courierId,
          deliveryId: snapshot.deliveryId,
          shiftId: snapshot.shiftId,
          type: CourierEventType.locationSnapshotRecorded,
          idempotencyKey: '${snapshot.id}-location',
          occurredAt: snapshot.capturedAt,
          sourceDeviceId: snapshot.deviceId,
        );
      }

      await _queueRepository.markSynced(snapshot.id, syncedAt: now);
      results.add(queued.copyWith(
        status: QueuedLocationSyncStatus.synced,
        syncedAt: now,
      ));
    }

    return results;
  }
}
