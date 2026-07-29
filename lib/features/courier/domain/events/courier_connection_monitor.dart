import '../device/courier_device.dart';

/// Tracks courier device connectivity via a heartbeat contract — mirrors
/// `KitchenConnectionMonitor`'s shape as a deliberately separate type.
abstract interface class CourierConnectionMonitor {
  Future<void> recordHeartbeat({
    required String deviceId,
    required DateTime at,
  });

  Future<bool> isStale({
    required String deviceId,
    required Duration staleAfter,
    required DateTime now,
  });

  Future<List<CourierDevice>> findStaleDevices({
    required String branchId,
    required Duration staleAfter,
    required DateTime now,
  });
}
