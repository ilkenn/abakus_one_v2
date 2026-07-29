import '../domain/location/location_emergency_override.dart';

/// Append-only storage for [LocationEmergencyOverride] — no update or
/// delete method; immutable once granted.
abstract interface class LocationEmergencyOverrideRepository {
  Future<void> append(LocationEmergencyOverride override);

  /// Every override ever granted to [courierId], newest first.
  Future<List<LocationEmergencyOverride>> findByCourierId(String courierId);
}

class InMemoryLocationEmergencyOverrideRepository
    implements LocationEmergencyOverrideRepository {
  final List<LocationEmergencyOverride> _all = [];

  @override
  Future<void> append(LocationEmergencyOverride override) async {
    _all.add(override);
  }

  @override
  Future<List<LocationEmergencyOverride>> findByCourierId(
      String courierId) async {
    final matches = _all.where((o) => o.courierId == courierId).toList();
    return List.unmodifiable(matches.reversed);
  }
}
