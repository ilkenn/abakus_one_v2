import '../../../../shared/models/money.dart';
import '../../../orders/domain/models/order_id.dart';

/// One immutable, computed-once earnings record for a single completed
/// [Delivery] — package fee plus chargeable extra-distance earnings,
/// calculated from the [CourierCompensationProfile] that was
/// [CourierCompensationProfile.coversAt] the delivery's completion time
/// (never the courier's *current* rates). Written once by
/// `CalculateDeliveryEarnings`, which is itself idempotent — a repeated
/// call for the same [deliveryId] returns the existing record unchanged
/// rather than recomputing, so this type never needs an update method at
/// all: **"locked" is structural, not a flag**.
class DeliveryEarnings {
  const DeliveryEarnings({
    required this.id,
    required this.deliveryId,
    required this.courierId,
    required this.orderId,
    required this.compensationProfileId,
    required this.compensationProfileVersion,
    required this.packageFee,
    required this.distanceKm,
    required this.freeDistanceKm,
    required this.extraDistanceKm,
    required this.extraDistanceEarnings,
    required this.totalEarnings,
    this.wasManagerApprovedCancellation = false,
    this.approvalReason,
    required this.calculatedAt,
  });

  final String id;
  final String deliveryId;
  final String courierId;
  final OrderId orderId;
  final String compensationProfileId;
  final int compensationProfileVersion;

  final Money packageFee;

  /// The delivery's own distance, in kilometers — sourced from
  /// `DeliveryRouteSnapshot.distanceEstimateMeters` when one exists, `0`
  /// otherwise. See this type's own doc comment
  /// (`delivery_route_snapshot.dart`) for its documented "informational,
  /// non-authoritative" status — reused here for lack of any other
  /// distance source in this codebase; see `docs/decisions.md` ADR-018.
  final double distanceKm;

  /// Snapshot of the profile's [CourierCompensationProfile.freeDistanceKm]
  /// at calculation time — frozen, so a later rate change never
  /// retroactively changes an already-calculated delivery's earnings.
  final double freeDistanceKm;

  /// `max(0, distanceKm - freeDistanceKm)` — never negative.
  final double extraDistanceKm;

  final Money extraDistanceEarnings;

  /// `packageFee + extraDistanceEarnings`.
  final Money totalEarnings;

  /// `true` only when this delivery was `DeliveryStatus.cancelled` and a
  /// manager explicitly approved package earnings anyway — "cancelled
  /// deliveries do not generate package earnings unless manager-approved."
  final bool wasManagerApprovedCancellation;
  final String? approvalReason;

  final DateTime calculatedAt;
}
