import 'package:connectivity_plus/connectivity_plus.dart' as connectivity_plus;

import '../domain/location/network_connectivity_monitor.dart';

/// Real, device-backed [NetworkConnectivityMonitor] — Sprint 5B, wraps
/// `package:connectivity_plus`.
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
