import 'dart:math' as math;

import 'courier_location_snapshot.dart';
import '../delivery/delivery_route_snapshot.dart';

/// Produces a non-authoritative [DeliveryRouteSnapshot] estimate — never a
/// real routing/mapping-provider integration (none is approved). The only
/// implementation this phase, [NaiveEtaEstimator], uses straight-line
/// (haversine) distance and a fixed assumed speed — explicitly a rough
/// placeholder, not real route-aware ETA.
abstract interface class EtaEstimator {
  DeliveryRouteSnapshot estimate({
    required String id,
    required String deliveryId,
    required CourierLocationSnapshot from,
    required double targetLatitude,
    required double targetLongitude,
    required DateTime now,
  });
}

/// Straight-line-distance-based estimate at an assumed average speed —
/// deliberately crude; real ETA needs a routing provider this phase does
/// not add.
class NaiveEtaEstimator implements EtaEstimator {
  const NaiveEtaEstimator({this.assumedSpeedMetersPerSecond = 6});

  /// ~21.6 km/h — a rough moped/bicycle average, not a real speed model.
  final double assumedSpeedMetersPerSecond;

  @override
  DeliveryRouteSnapshot estimate({
    required String id,
    required String deliveryId,
    required CourierLocationSnapshot from,
    required double targetLatitude,
    required double targetLongitude,
    required DateTime now,
  }) {
    final distance = _distanceMeters(
      from.latitude,
      from.longitude,
      targetLatitude,
      targetLongitude,
    );
    final etaSeconds = distance / assumedSpeedMetersPerSecond;
    return DeliveryRouteSnapshot(
      id: id,
      deliveryId: deliveryId,
      distanceEstimateMeters: distance,
      etaMinutes: (etaSeconds / 60).ceil(),
      computedAt: now,
    );
  }

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _rad(double d) => d * math.pi / 180;
}
