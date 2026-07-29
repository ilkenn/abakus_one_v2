/// Requested GPS accuracy/power tradeoff for a [CourierLocationProvider]
/// stream — "high accuracy" vs. "balanced accuracy" (Sprint 5B Part 1).
/// A platform implementation maps this to its own native accuracy enum
/// (e.g. `geolocator`'s `LocationAccuracy`); the domain layer never
/// depends on that native type directly.
enum LocationTrackingAccuracy {
  /// Best available fix — highest battery cost. Used when
  /// [AdaptiveTrackingPolicy] determines the courier is approaching a
  /// geofence target.
  high,

  /// The default — a reasonable accuracy/battery tradeoff for routine
  /// tracking.
  balanced,

  /// Coarser, lowest battery cost — used while stationary.
  low,
}
