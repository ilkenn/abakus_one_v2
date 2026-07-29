/// A device's current synchronization standing — **computed on demand,
/// never persisted as authoritative data**. Mirrors
/// `KitchenSynchronizationState`'s shape and reasoning as a separate type.
class CourierSynchronizationState {
  const CourierSynchronizationState({
    required this.deviceId,
    required this.isSynchronized,
    required this.lastSyncedAt,
    required this.pendingEventCount,
    required this.isStale,
  });

  final String deviceId;
  final bool isSynchronized;
  final DateTime? lastSyncedAt;
  final int pendingEventCount;
  final bool isStale;
}
