import '../domain/location/geofence_override.dart';

/// Append-only storage for [GeofenceOverride] — no update/delete method.
abstract interface class GeofenceOverrideRepository {
  Future<void> append(GeofenceOverride override);
  Future<List<GeofenceOverride>> findByDeliveryId(String deliveryId);
}

class InMemoryGeofenceOverrideRepository implements GeofenceOverrideRepository {
  final List<GeofenceOverride> _overrides = [];

  @override
  Future<void> append(GeofenceOverride override) async {
    _overrides.add(override);
  }

  @override
  Future<List<GeofenceOverride>> findByDeliveryId(String deliveryId) async {
    return List.unmodifiable(
      _overrides.where((o) => o.deliveryId == deliveryId),
    );
  }
}
