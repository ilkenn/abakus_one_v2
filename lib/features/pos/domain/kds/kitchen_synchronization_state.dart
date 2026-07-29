/// A device's current synchronization standing relative to the branch's
/// kitchen event log — **computed on demand by `KitchenSynchronizationService`,
/// never persisted as authoritative data**. Re-derived every time a
/// device asks "am I in sync?" from its [KitchenEventCursor] plus the
/// event log's current highest sequence, so it can never itself drift out
/// of date the way a stored flag could.
class KitchenSynchronizationState {
  const KitchenSynchronizationState({
    required this.deviceId,
    required this.isSynchronized,
    required this.lastSyncedAt,
    required this.pendingEventCount,
    required this.isStale,
  });

  final String deviceId;

  /// `true` once [pendingEventCount] is `0` — the device's cursor has
  /// caught up to the log's latest sequence.
  final bool isSynchronized;

  final DateTime? lastSyncedAt;

  /// How many events with `sequence > cursor.lastProcessedSequence`
  /// remain to be replayed to this device.
  final int pendingEventCount;

  /// Whether this device's connection is stale per
  /// `KitchenConnectionMonitor` — independent of [isSynchronized] (a
  /// device can be caught up but still stale if its heartbeat lapsed).
  final bool isStale;
}
