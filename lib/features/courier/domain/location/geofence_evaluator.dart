import 'dart:math' as math;

import 'courier_location_snapshot.dart';
import 'geofence_evaluation_result.dart';

/// Evaluates a [CourierLocationSnapshot] against a target lat/lng and
/// radius — a pure function, no I/O, mirrors `KitchenRoutingResolver`/
/// `ExpeditorProjectionBuilder`'s shape. Uses the haversine great-circle
/// distance formula (no mapping-provider dependency needed for this).
abstract final class GeofenceEvaluator {
  GeofenceEvaluator._();

  /// Default operational target radius, per the explicit requirement
  /// ("default operational target around 20 metres where appropriate").
  static const double defaultRadiusMeters = 20;

  /// A reading coarser than this is never trusted as definitive evidence.
  static const double maxTrustedAccuracyMeters = 50;

  static const double _earthRadiusMeters = 6371000;

  static GeofenceEvaluationResult evaluate({
    required CourierLocationSnapshot snapshot,
    required double targetLatitude,
    required double targetLongitude,
    double radiusMeters = defaultRadiusMeters,
  }) {
    final distance = _haversineDistanceMeters(
      snapshot.latitude,
      snapshot.longitude,
      targetLatitude,
      targetLongitude,
    );
    return GeofenceEvaluationResult(
      isWithin: distance <= radiusMeters,
      distanceMeters: distance,
      isAccuracySufficient: snapshot.accuracyMeters <= maxTrustedAccuracyMeters,
    );
  }

  static double _haversineDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  static double _degreesToRadians(double degrees) => degrees * math.pi / 180;
}
