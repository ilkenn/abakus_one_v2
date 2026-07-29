import '../location/courier_location_snapshot.dart';
import '../location/geofence_evaluator.dart';

/// Finds the earliest [CourierLocationSnapshot.capturedAt] among a set of
/// readings that genuinely passes a geofence check — "do not trust one GPS
/// point": every candidate is independently evaluated (accuracy,
/// timestamp, position) via the unmodified [GeofenceEvaluator], and only
/// the first whose [GeofenceEvaluationResult.passesAutomatically] is
/// `true` counts. A single low-accuracy or out-of-radius point is never
/// enough — "low accuracy GPS cannot become financial evidence." A pure
/// function, no I/O, reuses [GeofenceEvaluator] unchanged.
abstract final class FirstVerifiedGeofenceArrivalFinder {
  FirstVerifiedGeofenceArrivalFinder._();

  static DateTime? find({
    required List<CourierLocationSnapshot> snapshots,
    required double targetLatitude,
    required double targetLongitude,
    double radiusMeters = GeofenceEvaluator.defaultRadiusMeters,
  }) {
    final sorted = [...snapshots]
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    for (final snapshot in sorted) {
      final result = GeofenceEvaluator.evaluate(
        snapshot: snapshot,
        targetLatitude: targetLatitude,
        targetLongitude: targetLongitude,
        radiusMeters: radiusMeters,
      );
      if (result.passesAutomatically) return snapshot.capturedAt;
    }
    return null;
  }
}
