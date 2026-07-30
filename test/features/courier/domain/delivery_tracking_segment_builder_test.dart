import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_tracking_segment_builder.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_tracking_segment_type.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

CourierLocationSnapshot _snapshot({
  required String id,
  double latitude = 41.0,
  double longitude = 29.0,
  required DateTime capturedAt,
}) {
  return CourierLocationSnapshot(
    id: id,
    courierId: 'courier-1',
    deviceId: 'device-1',
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: 10,
    capturedAt: capturedAt,
    receivedAt: capturedAt,
  );
}

void main() {
  group('DeliveryTrackingSegmentBuilder.build', () {
    test('fewer than two readings produces no segments', () {
      final segments = DeliveryTrackingSegmentBuilder.build(history: [
        _snapshot(id: 'loc-1', capturedAt: DateTime(2026, 1, 1, 12)),
      ]);
      expect(segments, isEmpty);
    });

    test('a moving pair is classified as travel', () {
      final segments = DeliveryTrackingSegmentBuilder.build(history: [
        _snapshot(
          id: 'loc-1',
          latitude: 41.0,
          capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
        ),
        _snapshot(
          id: 'loc-2',
          latitude: 41.001,
          capturedAt: DateTime(2026, 1, 1, 12, 0, 10),
        ),
      ]);
      expect(segments, hasLength(1));
      expect(segments.single.type, DeliveryTrackingSegmentType.travel);
      expect(segments.single.distanceMeters, greaterThan(0));
    });

    test('a stationary pair is classified as a stop', () {
      final segments = DeliveryTrackingSegmentBuilder.build(history: [
        _snapshot(
          id: 'loc-1',
          latitude: 41.0,
          capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
        ),
        _snapshot(
          id: 'loc-2',
          latitude: 41.0,
          capturedAt: DateTime(2026, 1, 1, 12, 5, 0),
        ),
      ]);
      expect(segments.single.type, DeliveryTrackingSegmentType.stop);
      expect(segments.single.averageSpeedMetersPerSecond, 0);
    });

    test('unsorted input is sorted by capturedAt before building segments', () {
      final segments = DeliveryTrackingSegmentBuilder.build(history: [
        _snapshot(
          id: 'loc-2',
          latitude: 41.001,
          capturedAt: DateTime(2026, 1, 1, 12, 0, 10),
        ),
        _snapshot(
          id: 'loc-1',
          latitude: 41.0,
          capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
        ),
      ]);
      expect(segments, hasLength(1));
      expect(segments.single.startAt, DateTime(2026, 1, 1, 12, 0, 0));
      expect(segments.single.endAt, DateTime(2026, 1, 1, 12, 0, 10));
    });

    test('three readings produce two consecutive segments', () {
      final segments = DeliveryTrackingSegmentBuilder.build(history: [
        _snapshot(
          id: 'loc-1',
          latitude: 41.0,
          capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
        ),
        _snapshot(
          id: 'loc-2',
          latitude: 41.001,
          capturedAt: DateTime(2026, 1, 1, 12, 0, 10),
        ),
        _snapshot(
          id: 'loc-3',
          latitude: 41.002,
          capturedAt: DateTime(2026, 1, 1, 12, 0, 20),
        ),
      ]);
      expect(segments, hasLength(2));
    });

    test('the stop threshold is adjustable, never hardcoded', () {
      final segments = DeliveryTrackingSegmentBuilder.build(
        history: [
          _snapshot(
            id: 'loc-1',
            latitude: 41.0,
            capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
          ),
          _snapshot(
            id: 'loc-2',
            latitude: 41.0001,
            capturedAt: DateTime(2026, 1, 1, 12, 0, 10),
          ),
        ],
        stopSpeedThresholdMetersPerSecond: 100,
      );
      // A very high threshold forces even real movement to read as a stop.
      expect(segments.single.type, DeliveryTrackingSegmentType.stop);
    });
  });
}
