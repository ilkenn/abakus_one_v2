/// Coarse device network reachability — distinct from
/// `CourierConnectionMonitor` (Phase 5's app-level connection-health
/// signal to the backend itself). This is the lower-level, platform-
/// reported radio status feeding Part 6 ("connection health") and Part 7
/// (offline queue: when to attempt a reconnect sync). Sprint 5B.
enum NetworkConnectivityStatus { online, offline }

abstract interface class NetworkConnectivityMonitor {
  Future<NetworkConnectivityStatus> currentStatus();

  /// Fires whenever device-level connectivity changes.
  Stream<NetworkConnectivityStatus> get onStatusChanged;
}

/// Honest "always offline" default for tests/environments with no real
/// device — never fabricates an "online" signal.
class NoOpNetworkConnectivityMonitor implements NetworkConnectivityMonitor {
  const NoOpNetworkConnectivityMonitor();

  @override
  Future<NetworkConnectivityStatus> currentStatus() async =>
      NetworkConnectivityStatus.offline;

  @override
  Stream<NetworkConnectivityStatus> get onStatusChanged => const Stream.empty();
}
