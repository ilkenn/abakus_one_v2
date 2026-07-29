import 'location_tracking_accuracy.dart';
import 'movement_state.dart';

/// Maps a courier's current motion to a GPS update interval/accuracy —
/// Sprint 5B Part 3 ("battery optimization"). A pure, stateless calculator
/// (mirrors `GeofenceEvaluator`/`NaiveEtaEstimator`'s shape): no I/O, no
/// platform dependency.
///
/// Every threshold and interval is a constructor field with a documented
/// default matching the brief's example policy (standing still 30s,
/// walking 10s, vehicle 5s, approaching target 2s) — **never hardcoded
/// inside [intervalFor]/[classify]**, so operators can retune the policy
/// (e.g. per branch, per device battery level) without a code change.
class AdaptiveTrackingPolicy {
  const AdaptiveTrackingPolicy({
    this.stationaryInterval = const Duration(seconds: 30),
    this.walkingInterval = const Duration(seconds: 10),
    this.vehicleInterval = const Duration(seconds: 5),
    this.approachingTargetInterval = const Duration(seconds: 2),
    this.walkingSpeedThresholdMetersPerSecond = 0.5,
    this.vehicleSpeedThresholdMetersPerSecond = 3.0,
    this.approachingTargetRadiusMeters = 300,
  });

  final Duration stationaryInterval;
  final Duration walkingInterval;
  final Duration vehicleInterval;
  final Duration approachingTargetInterval;

  /// Below this speed (m/s), the courier is classified [MovementState.stationary].
  final double walkingSpeedThresholdMetersPerSecond;

  /// At or above this speed (m/s), the courier is classified
  /// [MovementState.vehicle]; between the two thresholds is
  /// [MovementState.walking].
  final double vehicleSpeedThresholdMetersPerSecond;

  /// Distance to the courier's current active geofence target within
  /// which [MovementState.approachingTarget] overrides the speed-based
  /// classification.
  final double approachingTargetRadiusMeters;

  /// [distanceToActiveTargetMeters] is `null` when the courier has no
  /// active pickup/delivery target to approach (e.g. idle between
  /// deliveries) — in that case only speed drives the classification.
  MovementState classify({
    required double speedMetersPerSecond,
    double? distanceToActiveTargetMeters,
  }) {
    if (distanceToActiveTargetMeters != null &&
        distanceToActiveTargetMeters <= approachingTargetRadiusMeters) {
      return MovementState.approachingTarget;
    }
    if (speedMetersPerSecond < walkingSpeedThresholdMetersPerSecond) {
      return MovementState.stationary;
    }
    if (speedMetersPerSecond < vehicleSpeedThresholdMetersPerSecond) {
      return MovementState.walking;
    }
    return MovementState.vehicle;
  }

  Duration intervalFor(MovementState state) {
    switch (state) {
      case MovementState.stationary:
        return stationaryInterval;
      case MovementState.walking:
        return walkingInterval;
      case MovementState.vehicle:
        return vehicleInterval;
      case MovementState.approachingTarget:
        return approachingTargetInterval;
    }
  }

  /// Stationary/walking use [LocationTrackingAccuracy.low]/`.balanced` —
  /// there's no reason to pay GPS's highest battery cost while barely
  /// moving. [MovementState.approachingTarget] always requests `.high` —
  /// this is exactly the moment geofence precision matters most.
  LocationTrackingAccuracy accuracyFor(MovementState state) {
    switch (state) {
      case MovementState.stationary:
        return LocationTrackingAccuracy.low;
      case MovementState.walking:
      case MovementState.vehicle:
        return LocationTrackingAccuracy.balanced;
      case MovementState.approachingTarget:
        return LocationTrackingAccuracy.high;
    }
  }
}
