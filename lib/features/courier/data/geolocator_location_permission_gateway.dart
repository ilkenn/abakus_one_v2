import 'package:geolocator/geolocator.dart' as geo;

import '../domain/location/location_permission_gateway.dart';

/// Real, device-backed [LocationPermissionGateway] — Sprint 5B Part 1.
/// Wraps `package:geolocator`'s permission/service APIs; never leaks
/// `geolocator`'s own [geo.LocationPermission] type outside this file —
/// callers only ever see [LocationPermissionState].
class GeolocatorLocationPermissionGateway implements LocationPermissionGateway {
  const GeolocatorLocationPermissionGateway();

  /// `deniedForever` has no exact match in [LocationPermissionState] — it
  /// is mapped to [LocationPermissionState.restricted] because, like a
  /// platform-level restriction, the app can no longer prompt for it; the
  /// user must leave the app to resolve it (Settings), which is the
  /// behaviorally relevant distinction for every caller of this gateway.
  static LocationPermissionState _map(geo.LocationPermission permission) {
    switch (permission) {
      case geo.LocationPermission.denied:
        return LocationPermissionState.denied;
      case geo.LocationPermission.deniedForever:
        return LocationPermissionState.restricted;
      case geo.LocationPermission.whileInUse:
      case geo.LocationPermission.always:
        return LocationPermissionState.granted;
      case geo.LocationPermission.unableToDetermine:
        return LocationPermissionState.notDetermined;
    }
  }

  @override
  Future<LocationPermissionState> currentState() async {
    final permission = await geo.Geolocator.checkPermission();
    return _map(permission);
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    final permission = await geo.Geolocator.requestPermission();
    return _map(permission);
  }

  @override
  Future<bool> isLocationServiceEnabled() =>
      geo.Geolocator.isLocationServiceEnabled();

  @override
  Future<bool> hasBackgroundPermission() async {
    final permission = await geo.Geolocator.checkPermission();
    return permission == geo.LocationPermission.always;
  }

  /// `geolocator` exposes a single [geo.Geolocator.requestPermission] for
  /// both foreground and background — the OS itself decides whether to
  /// show the foreground or the "upgrade to Always" prompt based on the
  /// permission already granted. There is no separate native
  /// background-only request call to delegate to.
  @override
  Future<bool> requestBackgroundPermission() async {
    final permission = await geo.Geolocator.requestPermission();
    return permission == geo.LocationPermission.always;
  }
}
