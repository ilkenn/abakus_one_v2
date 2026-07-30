import '../domain/location/courier_location_snapshot.dart';
import '../domain/location/queued_courier_location.dart';
import '../domain/location/queued_location_sync_status.dart';

/// The device-local buffer of [CourierLocationSnapshot]s captured while
/// offline — Sprint 5B Part 7. Distinct from `CourierLocationRepository`
/// (the synced, canonical/"received" history): this repository represents
/// what one device is still holding onto, not yet acknowledged.
abstract interface class OfflineLocationQueueRepository {
  /// Idempotent by [CourierLocationSnapshot.id] — enqueuing the same
  /// reading twice (e.g. a provider retry before the first enqueue was
  /// confirmed) never creates a duplicate queue entry.
  Future<void> enqueue(CourierLocationSnapshot snapshot);

  /// Ordered oldest-first by [CourierLocationSnapshot.capturedAt] —
  /// "ordering guarantees": a sync always replays in the order the device
  /// actually captured the readings, never insertion/arrival order.
  Future<List<QueuedCourierLocation>> findPendingByDeviceId(String deviceId);

  Future<void> markSynced(String snapshotId, {required DateTime syncedAt});
  Future<void> markFailed(String snapshotId, {required String reason});
}

class InMemoryOfflineLocationQueueRepository
    implements OfflineLocationQueueRepository {
  final Map<String, QueuedCourierLocation> _byId = {};

  @override
  Future<void> enqueue(CourierLocationSnapshot snapshot) async {
    _byId.putIfAbsent(
      snapshot.id,
      () => QueuedCourierLocation(snapshot: snapshot),
    );
  }

  @override
  Future<List<QueuedCourierLocation>> findPendingByDeviceId(
      String deviceId) async {
    final pending = _byId.values
        .where((q) =>
            q.snapshot.deviceId == deviceId &&
            q.status == QueuedLocationSyncStatus.pending)
        .toList()
      ..sort((a, b) => a.snapshot.capturedAt.compareTo(b.snapshot.capturedAt));
    return List.unmodifiable(pending);
  }

  @override
  Future<void> markSynced(String snapshotId,
      {required DateTime syncedAt}) async {
    final existing = _byId[snapshotId];
    if (existing == null) return;
    _byId[snapshotId] = existing.copyWith(
      status: QueuedLocationSyncStatus.synced,
      syncedAt: syncedAt,
    );
  }

  @override
  Future<void> markFailed(String snapshotId, {required String reason}) async {
    final existing = _byId[snapshotId];
    if (existing == null) return;
    _byId[snapshotId] = existing.copyWith(
      status: QueuedLocationSyncStatus.failed,
      failureReason: reason,
    );
  }
}
