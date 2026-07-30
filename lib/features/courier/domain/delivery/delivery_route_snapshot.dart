import '../location/geofence_zone_type.dart';

/// A **non-authoritative** distance/ETA estimate for one [Delivery] —
/// "ETA must be an estimate, not authoritative truth." Never used to
/// validate/block any delivery-lifecycle transition; purely informational
/// for UI display. Immutable — a new estimate is a new snapshot, never an
/// edit of a previous one.
///
/// **Sprint 5B**: [zoneType], [confidenceScore], and
/// [trafficMultiplierApplied] are additive, optional fields —
/// `NaiveEtaEstimator` (Phase 5) never sets them and remains valid;
/// `AdaptiveEtaEstimator` (Sprint 5B) populates all three.
class DeliveryRouteSnapshot {
  const DeliveryRouteSnapshot({
    required this.id,
    required this.deliveryId,
    this.distanceEstimateMeters,
    this.etaMinutes,
    required this.computedAt,
    this.zoneType,
    this.confidenceScore,
    this.trafficMultiplierApplied,
  });

  final String id;
  final String deliveryId;
  final double? distanceEstimateMeters;
  final int? etaMinutes;
  final DateTime computedAt;

  /// Which checkpoint this estimate is for (restaurant/pickup/customer) —
  /// `null` for an estimate that predates this distinction (Phase 5).
  final GeofenceZoneType? zoneType;

  /// 0.0-1.0, higher is more trustworthy — reflects whether a historical
  /// average could be used (vs. the fixed assumed-speed fallback) and the
  /// source snapshot's GPS accuracy. Never a claim of statistical rigor,
  /// purely an ordering signal for UI display.
  final double? confidenceScore;

  /// The traffic multiplier actually applied to reach [etaMinutes] from
  /// the raw distance/speed estimate — `null` when no
  /// [TrafficMultiplierProvider] was used (e.g. `NaiveEtaEstimator`), `1.0`
  /// when one was used but applied no adjustment.
  final double? trafficMultiplierApplied;
}
