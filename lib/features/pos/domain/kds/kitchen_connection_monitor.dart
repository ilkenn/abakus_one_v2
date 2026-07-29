import 'kitchen_display_device.dart';

/// Tracks device connectivity via the heartbeat contract Phase 4G
/// requires — staleness is always computed from
/// [KitchenDisplaySession.lastHeartbeatAt] plus a caller-supplied
/// threshold and `Clock`, never stored as a standalone "is connected"
/// flag that could go stale itself.
abstract interface class KitchenConnectionMonitor {
  /// Records a heartbeat for [deviceId]'s current active session —
  /// throws if the device has no active session (it must call
  /// `StartKitchenDisplaySession` first).
  Future<void> recordHeartbeat({
    required String deviceId,
    required DateTime at,
  });

  /// `true` if [deviceId]'s active session's last heartbeat is older than
  /// [staleAfter] relative to [now].
  Future<bool> isStale({
    required String deviceId,
    required Duration staleAfter,
    required DateTime now,
  });

  /// Every device in [branchId] whose active session is stale per
  /// [staleAfter]/[now] — what a branch-wide "which screens went dark"
  /// check reads.
  Future<List<KitchenDisplayDevice>> findStaleDevices({
    required String branchId,
    required Duration staleAfter,
    required DateTime now,
  });
}
