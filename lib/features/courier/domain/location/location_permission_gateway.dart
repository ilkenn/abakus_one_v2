/// Backend/platform-neutral seam for location-permission state — a real
/// implementation would wrap platform permission APIs; **none exists this
/// phase** (no such package is a dependency). [NoOpLocationPermissionGateway]
/// is the only implementation — always reports "not granted," the honest
/// default rather than a fabricated "always allowed."
enum LocationPermissionState { notDetermined, denied, granted, restricted }

abstract interface class LocationPermissionGateway {
  Future<LocationPermissionState> currentState();
  Future<LocationPermissionState> requestPermission();
}

class NoOpLocationPermissionGateway implements LocationPermissionGateway {
  const NoOpLocationPermissionGateway();

  @override
  Future<LocationPermissionState> currentState() async =>
      LocationPermissionState.notDetermined;

  @override
  Future<LocationPermissionState> requestPermission() async =>
      LocationPermissionState.denied;
}
