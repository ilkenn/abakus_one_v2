import 'geofence_zone_type.dart';

/// One named geofence target — Sprint 5B Part 4 ("multiple simultaneous
/// geofences"). A delivery typically has several active zones at once
/// (its restaurant, its customer address, occasionally a package-pickup
/// point distinct from the restaurant itself); [MultiGeofenceEvaluator]
/// evaluates a single [CourierLocationSnapshot] against all of them in one
/// pass rather than one target at a time.
class GeofenceZone {
  const GeofenceZone({
    required this.zoneType,
    required this.targetLatitude,
    required this.targetLongitude,
    required this.radiusMeters,
    this.label,
  });

  final GeofenceZoneType zoneType;
  final double targetLatitude;
  final double targetLongitude;

  /// Dynamic radius — deliberately per-zone, not a single app-wide
  /// constant, so e.g. a large shopping-mall restaurant or a dense
  /// apartment-block customer address can be configured wider than
  /// `GeofenceEvaluator.defaultRadiusMeters` without a code change.
  final double radiusMeters;

  /// Optional human-readable identifier (e.g. a branch/address label) for
  /// audit trails and manager UI — never used in evaluation logic itself.
  final String? label;
}
