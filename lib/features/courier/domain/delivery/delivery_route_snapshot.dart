/// A **non-authoritative** distance/ETA estimate for one [Delivery] —
/// "ETA must be an estimate, not authoritative truth." Never used to
/// validate/block any delivery-lifecycle transition; purely informational
/// for UI display. Immutable — a new estimate is a new snapshot, never an
/// edit of a previous one.
class DeliveryRouteSnapshot {
  const DeliveryRouteSnapshot({
    required this.id,
    required this.deliveryId,
    this.distanceEstimateMeters,
    this.etaMinutes,
    required this.computedAt,
  });

  final String id;
  final String deliveryId;
  final double? distanceEstimateMeters;
  final int? etaMinutes;
  final DateTime computedAt;
}
