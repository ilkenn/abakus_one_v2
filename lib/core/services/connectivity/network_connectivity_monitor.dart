/// Generic, feature-agnostic "is the device online" signal — Self-Order QR
/// Faz 6. Deliberately placed in `core/services/` rather than reusing
/// `features/courier/domain/location/network_connectivity_monitor.dart`
/// (an existing, structurally-identical interface) — CLAUDE.md §3 forbids
/// one feature depending on another's domain layer, and `connectivity_plus`
/// itself has nothing courier-specific about it.
enum NetworkConnectivityStatus { online, offline }

abstract interface class NetworkConnectivityMonitor {
  Future<NetworkConnectivityStatus> currentStatus();
  Stream<NetworkConnectivityStatus> get onStatusChanged;
}
