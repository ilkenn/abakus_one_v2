import '../audit/courier_operational_audit_entry.dart';
import '../location/courier_location_snapshot.dart';
import 'delivery_tracking_segment.dart';
import 'delivery_tracking_segment_type.dart';

/// The full assembled tracking history for one delivery — Sprint 5B Part
/// 10. [checkpoints] are the existing `CourierOperationalAuditEntry`
/// records already produced by `TransitionDelivery`/`ConfirmPackagePickup`
/// /`CompleteDelivery` (accepted → arrived at restaurant → picked up →
/// en route → arrived at customer → delivered), reused unchanged — this
/// type adds no new checkpoint-recording logic, only assembles what
/// already exists alongside the location/travel/stop/speed trace.
class DeliveryTrackingHistory {
  const DeliveryTrackingHistory({
    required this.deliveryId,
    required this.checkpoints,
    required this.locationHistory,
    required this.segments,
  });

  final String deliveryId;

  /// Oldest first.
  final List<CourierOperationalAuditEntry> checkpoints;

  /// Oldest first.
  final List<CourierLocationSnapshot> locationHistory;

  final List<DeliveryTrackingSegment> segments;

  double get totalDistanceMeters =>
      segments.fold(0.0, (sum, s) => sum + s.distanceMeters);

  Duration get totalTravelDuration => segments
      .where((s) => s.type == DeliveryTrackingSegmentType.travel)
      .fold(Duration.zero, (sum, s) => sum + s.duration);

  Duration get totalStopDuration => segments
      .where((s) => s.type == DeliveryTrackingSegmentType.stop)
      .fold(Duration.zero, (sum, s) => sum + s.duration);
}
