import 'courier_location_snapshot.dart';
import 'geofence_evaluator.dart';
import 'geofence_zone.dart';
import 'geofence_zone_evaluation.dart';

/// Evaluates one [CourierLocationSnapshot] against every [GeofenceZone] a
/// delivery currently has active, in a single pass — Sprint 5B Part 4
/// ("multiple simultaneous geofences": restaurant, package pickup, and
/// customer address zones can all be relevant to the same reading, e.g. a
/// pickup point directly across the street from the customer). A pure
/// function, reuses the unmodified [GeofenceEvaluator] per zone — never
/// duplicates its accuracy/distance logic.
abstract final class MultiGeofenceEvaluator {
  MultiGeofenceEvaluator._();

  static List<GeofenceZoneEvaluation> evaluate({
    required CourierLocationSnapshot snapshot,
    required List<GeofenceZone> zones,
  }) {
    return zones
        .map((zone) => GeofenceZoneEvaluation(
              zone: zone,
              result: GeofenceEvaluator.evaluate(
                snapshot: snapshot,
                targetLatitude: zone.targetLatitude,
                targetLongitude: zone.targetLongitude,
                radiusMeters: zone.radiusMeters,
              ),
            ))
        .toList(growable: false);
  }
}
