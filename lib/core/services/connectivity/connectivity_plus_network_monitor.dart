import 'package:connectivity_plus/connectivity_plus.dart' as connectivity_plus;

import 'network_connectivity_monitor.dart';

/// Real, device-backed [NetworkConnectivityMonitor] — Self-Order QR Faz 6.
/// Mirrors `ConnectivityPlusNetworkMonitor`
/// (`features/courier/data/connectivity_plus_network_monitor.dart`)
/// exactly — that one stays untouched/courier-owned; this is `core`'s own
/// copy so `cart`/`qr` never import across into `courier`.
class ConnectivityPlusNetworkMonitor implements NetworkConnectivityMonitor {
  ConnectivityPlusNetworkMonitor()
      : _connectivity = connectivity_plus.Connectivity();

  final connectivity_plus.Connectivity _connectivity;

  static NetworkConnectivityStatus _map(
    List<connectivity_plus.ConnectivityResult> results,
  ) {
    final isOffline = results.every(
      (r) => r == connectivity_plus.ConnectivityResult.none,
    );
    return isOffline
        ? NetworkConnectivityStatus.offline
        : NetworkConnectivityStatus.online;
  }

  @override
  Future<NetworkConnectivityStatus> currentStatus() async {
    final results = await _connectivity.checkConnectivity();
    return _map(results);
  }

  @override
  Stream<NetworkConnectivityStatus> get onStatusChanged =>
      _connectivity.onConnectivityChanged.map(_map);
}
