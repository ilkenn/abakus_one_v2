import 'package:abakus_one_v2/features/courier/domain/compensation/first_verified_geofence_arrival_finder.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

CourierLocationSnapshot _snapshot({
  required DateTime capturedAt,
  double latitude = 41.0,
  double longitude = 29.0,
  double accuracyMeters = 10,
}) {
  return CourierLocationSnapshot(
    id: 'loc-$capturedAt',
    courierId: 'courier-1',
    deviceId: 'device-1',
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    capturedAt: capturedAt,
    receivedAt: capturedAt,
  );
}

void main() {
  group('FirstVerifiedGeofenceArrivalFinder', () {
    test(
        'a single low-accuracy point is never enough — returns null even '
        'though it is within radius', () {
      final result = FirstVerifiedGeofenceArrivalFinder.find(
        snapshots: [
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12), accuracyMeters: 100),
        ],
        targetLatitude: 41.0,
        targetLongitude: 29.0,
      );
      expect(result, isNull);
    });

    test(
        'a point outside the radius does not count even with good '
        'accuracy', () {
      final result = FirstVerifiedGeofenceArrivalFinder.find(
        snapshots: [
          _snapshot(
              capturedAt: DateTime(2026, 1, 1, 12),
              latitude: 41.1,
              longitude: 29.1),
        ],
        targetLatitude: 41.0,
        targetLongitude: 29.0,
      );
      expect(result, isNull);
    });

    test(
        'returns the earliest capturedAt among passing candidates, '
        'ignoring input order', () {
      final result = FirstVerifiedGeofenceArrivalFinder.find(
        snapshots: [
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 10)),
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 5)),
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 20)),
        ],
        targetLatitude: 41.0,
        targetLongitude: 29.0,
      );
      expect(result, DateTime(2026, 1, 1, 12, 5));
    });

    test(
        'an early low-accuracy point is skipped in favor of a later '
        'genuinely-passing one', () {
      final result = FirstVerifiedGeofenceArrivalFinder.find(
        snapshots: [
          _snapshot(
              capturedAt: DateTime(2026, 1, 1, 12, 0), accuracyMeters: 200),
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 5)),
        ],
        targetLatitude: 41.0,
        targetLongitude: 29.0,
      );
      expect(result, DateTime(2026, 1, 1, 12, 5));
    });
  });
}
