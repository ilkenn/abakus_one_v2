/// Backend/platform-neutral seam for location-permission state.
/// **Sprint 5B**: `GeolocatorLocationPermissionGateway`
/// (`lib/features/courier/data/geolocator_location_permission_gateway.dart`)
/// wraps the real `geolocator` permission APIs. [NoOpLocationPermissionGateway]
/// remains available — always reports "not granted," the honest default
/// rather than a fabricated "always allowed" — for tests/environments
/// with no real device.
enum LocationPermissionState { notDetermined, denied, granted, restricted }

abstract interface class LocationPermissionGateway {
  Future<LocationPermissionState> currentState();
  Future<LocationPermissionState> requestPermission();

  /// Whether the device's location *service* (GPS/network positioning) is
  /// turned on at all — distinct from app-level permission: a user can
  /// grant permission while the OS-wide location service remains off.
  Future<bool> isLocationServiceEnabled();

  /// Whether background ("Always"/`ACCESS_BACKGROUND_LOCATION`) permission
  /// has been granted, separately from foreground/"while in use" —
  /// requested only while a courier has an active shift, never implicitly
  /// (Sprint 5B Part 1).
  Future<bool> hasBackgroundPermission();

  /// Requests background permission specifically — on both platforms this
  /// is a distinct runtime step from [requestPermission] (foreground),
  /// and the OS requires foreground permission to already be granted
  /// before it can be requested.
  Future<bool> requestBackgroundPermission();
}

class NoOpLocationPermissionGateway implements LocationPermissionGateway {
  const NoOpLocationPermissionGateway();

  @override
  Future<LocationPermissionState> currentState() async =>
      LocationPermissionState.notDetermined;

  @override
  Future<LocationPermissionState> requestPermission() async =>
      LocationPermissionState.denied;

  @override
  Future<bool> isLocationServiceEnabled() async => false;

  @override
  Future<bool> hasBackgroundPermission() async => false;

  @override
  Future<bool> requestBackgroundPermission() async => false;
}
