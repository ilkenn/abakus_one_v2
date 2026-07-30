import 'dart:math' as math;

import '../delivery/delivery_route_snapshot.dart';
import 'courier_location_snapshot.dart';
import 'eta_estimator.dart';
import 'eta_historical_sample.dart';
import 'geofence_evaluator.dart';
import 'geofence_zone_type.dart';
import 'historical_eta_average_calculator.dart';
import 'traffic_multiplier_provider.dart';

/// A real, production-usable [EtaEstimator] — Sprint 5B Part 5. Builds on
/// exactly the same straight-line-distance approach as `NaiveEtaEstimator`
/// (Phase 5, unmodified) but adds three things the brief asks for: a
/// [HistoricalEtaAverageCalculator]-derived speed when enough history
/// exists (falling back to [assumedSpeedMetersPerSecond] otherwise), a
/// [TrafficMultiplierProvider] adjustment, and a [DeliveryRouteSnapshot
/// .confidenceScore]. **Still explicitly non-authoritative** — the class
/// doc on [DeliveryRouteSnapshot] ("ETA must be an estimate, not
/// authoritative truth") applies unchanged; this is a better estimate,
/// never a real routing/mapping-provider integration (none is approved).
class AdaptiveEtaEstimator implements EtaEstimator {
  const AdaptiveEtaEstimator({
    this.assumedSpeedMetersPerSecond = 6,
    this.trafficMultiplierProvider = const NoOpTrafficMultiplierProvider(),
    this.historicalSamples = const [],
    this.minimumHistoricalSampleCount = 5,
    this.zoneType,
  });

  /// ~21.6 km/h — the same rough moped/bicycle average `NaiveEtaEstimator`
  /// uses, and the fallback whenever [historicalSamples] doesn't yet meet
  /// [minimumHistoricalSampleCount].
  final double assumedSpeedMetersPerSecond;

  final TrafficMultiplierProvider trafficMultiplierProvider;

  /// Completed-leg samples for this route/branch, fetched by the caller
  /// before constructing this estimator — see
  /// [HistoricalEtaAverageCalculator].
  final List<EtaHistoricalSample> historicalSamples;
  final int minimumHistoricalSampleCount;

  /// Which checkpoint this estimator is producing an estimate for
  /// (restaurant/pickup/customer) — stamped onto the resulting
  /// [DeliveryRouteSnapshot.zoneType].
  final GeofenceZoneType? zoneType;

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

    final historicalSpeed =
        HistoricalEtaAverageCalculator.averageSpeedMetersPerSecond(
      samples: historicalSamples,
      minimumSampleCount: minimumHistoricalSampleCount,
    );
    final usedHistoricalSpeed = historicalSpeed != null;
    final speed = historicalSpeed ?? assumedSpeedMetersPerSecond;

    final multiplier = trafficMultiplierProvider.multiplierFor(now);
    final etaSeconds = (distance / speed) * multiplier;

    return DeliveryRouteSnapshot(
      id: id,
      deliveryId: deliveryId,
      distanceEstimateMeters: distance,
      etaMinutes: (etaSeconds / 60).ceil(),
      computedAt: now,
      zoneType: zoneType,
      confidenceScore: _confidenceScore(
        usedHistoricalSpeed: usedHistoricalSpeed,
        sourceAccuracyMeters: from.accuracyMeters,
      ),
      trafficMultiplierApplied: multiplier,
    );
  }

  /// A simple, documented ordering signal, not a statistical claim:
  /// starts from a base (straight-line estimates are never highly
  /// confident), adds a fixed bonus when a real historical average backed
  /// the speed used, and adds a fixed bonus when the source reading's
  /// accuracy is within `GeofenceEvaluator.maxTrustedAccuracyMeters`.
  static double _confidenceScore({
    required bool usedHistoricalSpeed,
    required double sourceAccuracyMeters,
  }) {
    const base = 0.4;
    const historicalBonus = 0.3;
    const accuracyBonus = 0.3;
    var score = base;
    if (usedHistoricalSpeed) score += historicalBonus;
    if (sourceAccuracyMeters <= GeofenceEvaluator.maxTrustedAccuracyMeters) {
      score += accuracyBonus;
    }
    return score.clamp(0.0, 1.0);
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
