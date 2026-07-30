import 'delivery_tracking_segment_type.dart';

/// One travel-or-stop segment between two consecutive
/// `CourierLocationSnapshot`s for a delivery — Sprint 5B Part 10.
/// Immutable, computed fresh by `DeliveryTrackingSegmentBuilder` every
/// time, never persisted itself (the underlying location readings remain
/// the source of truth).
class DeliveryTrackingSegment {
  const DeliveryTrackingSegment({
    required this.type,
    required this.startAt,
    required this.endAt,
    required this.distanceMeters,
    required this.averageSpeedMetersPerSecond,
  });

  final DeliveryTrackingSegmentType type;
  final DateTime startAt;
  final DateTime endAt;
  final double distanceMeters;
  final double averageSpeedMetersPerSecond;

  Duration get duration => endAt.difference(startAt);
}
