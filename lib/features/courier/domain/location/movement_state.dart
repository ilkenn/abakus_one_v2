/// Coarse motion classification used to pick a GPS update interval/accuracy
/// — Sprint 5B Part 3 ("battery optimization"). Derived by
/// [AdaptiveTrackingPolicy], never stored as its own persisted record.
enum MovementState {
  /// Speed below the walking threshold — the cheapest tracking tier.
  stationary,

  /// Speed between the walking and vehicle thresholds.
  walking,

  /// Speed at or above the vehicle threshold.
  vehicle,

  /// Within [AdaptiveTrackingPolicy.approachingTargetRadiusMeters] of the
  /// courier's current active geofence target (restaurant or customer) —
  /// always wins over the speed-based classification, since precision
  /// matters most right before an arrival/geofence check.
  approachingTarget,
}
