import 'geofence_evaluation_result.dart';
import 'geofence_zone.dart';

/// One [GeofenceZone] paired with its [GeofenceEvaluationResult] for a
/// single [CourierLocationSnapshot] — the per-zone output of
/// [MultiGeofenceEvaluator.evaluate].
class GeofenceZoneEvaluation {
  const GeofenceZoneEvaluation({
    required this.zone,
    required this.result,
  });

  final GeofenceZone zone;
  final GeofenceEvaluationResult result;
}
