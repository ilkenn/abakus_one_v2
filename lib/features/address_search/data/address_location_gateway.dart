import 'package:geolocator/geolocator.dart' as geo;

/// Faz P.2.1.2 (map-first UX) — one-shot device location for centering
/// the map-first address picker's initial camera position. Mirrors
/// `features/courier/data/geolocator_location_permission_gateway.dart`'s
/// own translation discipline: raw `geo.*` types never cross this
/// boundary, and every failure mode (permission denied, location
/// services disabled, any platform error) resolves to `null` rather than
/// throwing — this screen must never block address creation just
/// because location access isn't available (§5).
abstract interface class AddressLocationGateway {
  /// `null` if permission is denied/unavailable/undeterminable for any
  /// reason — never throws.
  Future<({double latitude, double longitude})?> currentPosition();

  /// `true` only when permission was permanently denied (the platform
  /// will never show the prompt again) — used to decide whether to show
  /// the "ayarlardan açabilirsiniz" hint versus staying silent.
  Future<bool> isPermissionPermanentlyDenied();
}

class GeolocatorAddressLocationGateway implements AddressLocationGateway {
  const GeolocatorAddressLocationGateway();

  @override
  Future<({double latitude, double longitude})?> currentPosition() async {
    try {
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied ||
          permission == geo.LocationPermission.deniedForever) {
        return null;
      }
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      final position = await geo.Geolocator.getCurrentPosition();
      return (latitude: position.latitude, longitude: position.longitude);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isPermissionPermanentlyDenied() async {
    try {
      final permission = await geo.Geolocator.checkPermission();
      return permission == geo.LocationPermission.deniedForever;
    } catch (_) {
      return false;
    }
  }
}
