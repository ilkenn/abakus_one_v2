import 'dart:math' as math;

import '../location/courier_location_snapshot.dart';
import 'delivery_tracking_segment.dart';
import 'delivery_tracking_segment_type.dart';

/// Builds [DeliveryTrackingSegment]s from a delivery's location history —
/// Sprint 5B Part 10's "location/travel/stop/speed history." A pure,
/// stateless calculator, no I/O — mirrors `GeofenceEvaluator`/
/// `NaiveEtaEstimator`'s shape.
abstract final class DeliveryTrackingSegmentBuilder {
  DeliveryTrackingSegmentBuilder._();

  /// Below this average speed (m/s), a segment is classified as a
  /// [DeliveryTrackingSegmentType.stop] rather than
  /// [DeliveryTrackingSegmentType.travel] — adjustable, never hardcoded.
  static const double defaultStopSpeedThresholdMetersPerSecond = 0.5;

  /// [history] does not need to be pre-sorted — this always sorts by
  /// [CourierLocationSnapshot.capturedAt] first, so segment ordering is
  /// never dependent on caller/storage insertion order.
  static List<DeliveryTrackingSegment> build({
    required List<CourierLocationSnapshot> history,
    double stopSpeedThresholdMetersPerSecond =
        defaultStopSpeedThresholdMetersPerSecond,
  }) {
    if (history.length < 2) return const [];
    final sorted = [...history]
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

    final segments = <DeliveryTrackingSegment>[];
    for (var i = 1; i < sorted.length; i++) {
      final previous = sorted[i - 1];
      final current = sorted[i];
      final seconds =
          current.capturedAt.difference(previous.capturedAt).inMilliseconds /
              1000;
      if (seconds <= 0) continue;

      final distance = _distanceMeters(
        previous.latitude,
        previous.longitude,
        current.latitude,
        current.longitude,
      );
      final averageSpeed = distance / seconds;
      segments.add(DeliveryTrackingSegment(
        type: averageSpeed < stopSpeedThresholdMetersPerSecond
            ? DeliveryTrackingSegmentType.stop
            : DeliveryTrackingSegmentType.travel,
        startAt: previous.capturedAt,
        endAt: current.capturedAt,
        distanceMeters: distance,
        averageSpeedMetersPerSecond: averageSpeed,
      ));
    }
    return segments;
  }

  static const double _earthRadiusMeters = 6371000;

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  static double _rad(double d) => d * math.pi / 180;
}
