import 'courier_location_snapshot.dart';
import 'queued_location_sync_status.dart';

/// One [CourierLocationSnapshot] captured while offline, held locally
/// until it can be synced — Sprint 5B Part 7's "queued locations." Wraps
/// the snapshot rather than duplicating its fields: the snapshot's own
/// [CourierLocationSnapshot.id] is what makes replay-deduplication
/// possible (it is never regenerated on retry, unlike
/// `RecordCourierLocationSnapshot`'s always-fresh id — see
/// `SyncQueuedCourierLocations`'s doc comment for why that use case is a
/// deliberate sibling, not a reuse, of the live-reporting path).
class QueuedCourierLocation {
  const QueuedCourierLocation({
    required this.snapshot,
    this.status = QueuedLocationSyncStatus.pending,
    this.syncedAt,
    this.failureReason,
  });

  final CourierLocationSnapshot snapshot;
  final QueuedLocationSyncStatus status;
  final DateTime? syncedAt;
  final String? failureReason;

  QueuedCourierLocation copyWith({
    QueuedLocationSyncStatus? status,
    DateTime? syncedAt,
    String? failureReason,
  }) {
    return QueuedCourierLocation(
      snapshot: snapshot,
      status: status ?? this.status,
      syncedAt: syncedAt ?? this.syncedAt,
      failureReason: failureReason ?? this.failureReason,
    );
  }
}
