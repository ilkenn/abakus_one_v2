import 'package:abakus_one_v2/features/courier/domain/fraud/courier_fraud_signal_detector.dart';
import 'package:abakus_one_v2/features/courier/domain/fraud/courier_fraud_signal_type.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

CourierLocationSnapshot _snapshot({
  double latitude = 41.0,
  double longitude = 29.0,
  double accuracyMeters = 10,
  required DateTime capturedAt,
  bool isMocked = false,
}) {
  return CourierLocationSnapshot(
    id: 'loc-1',
    courierId: 'courier-1',
    deviceId: 'device-1',
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    isMocked: isMocked,
    capturedAt: capturedAt,
    receivedAt: capturedAt,
  );
}

void main() {
  group('CourierFraudSignalDetector.detectImpossibleSpeed', () {
    test('a huge jump in a short time exceeding the max speed triggers', () {
      final previous = _snapshot(
        latitude: 41.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
      );
      final current = _snapshot(
        latitude: 41.1,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 1),
      );
      expect(
        CourierFraudSignalDetector.detectImpossibleSpeed(
          previous: previous,
          current: current,
        ),
        CourierFraudSignalType.impossibleSpeed,
      );
    });

    test('a plausible walking-speed movement never triggers', () {
      final previous = _snapshot(
        latitude: 41.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
      );
      final current = _snapshot(
        latitude: 41.00001,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 1),
      );
      expect(
        CourierFraudSignalDetector.detectImpossibleSpeed(
          previous: previous,
          current: current,
        ),
        isNull,
      );
    });

    test('low-accuracy readings never trigger a speed claim', () {
      final previous = _snapshot(
        latitude: 41.0,
        longitude: 29.0,
        accuracyMeters: 500,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
      );
      final current = _snapshot(
        latitude: 41.1,
        longitude: 29.0,
        accuracyMeters: 500,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 1),
      );
      expect(
        CourierFraudSignalDetector.detectImpossibleSpeed(
          previous: previous,
          current: current,
        ),
        isNull,
      );
    });

    test(
        'zero or negative elapsed time never triggers (never divides by '
        'zero)', () {
      final snapshot = _snapshot(capturedAt: DateTime(2026, 1, 1, 12));
      expect(
        CourierFraudSignalDetector.detectImpossibleSpeed(
          previous: snapshot,
          current: snapshot,
        ),
        isNull,
      );
    });
  });

  group('CourierFraudSignalDetector.detectGpsJump', () {
    test('a large jump within the window triggers', () {
      final previous = _snapshot(
        latitude: 41.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
      );
      final current = _snapshot(
        latitude: 41.01,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 2),
      );
      expect(
        CourierFraudSignalDetector.detectGpsJump(
          previous: previous,
          current: current,
        ),
        CourierFraudSignalType.gpsJump,
      );
    });

    test('the same jump outside the time window never triggers', () {
      final previous = _snapshot(
        latitude: 41.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
      );
      final current = _snapshot(
        latitude: 41.01,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 1, 0),
      );
      expect(
        CourierFraudSignalDetector.detectGpsJump(
          previous: previous,
          current: current,
        ),
        isNull,
      );
    });

    test('a small movement within the window never triggers', () {
      final previous = _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 0, 0));
      final current = _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 0, 2));
      expect(
        CourierFraudSignalDetector.detectGpsJump(
          previous: previous,
          current: current,
        ),
        isNull,
      );
    });
  });

  group('CourierFraudSignalDetector.detectUnrealisticTravel', () {
    test('an implied sustained speed above the max triggers', () {
      final start = _snapshot(
        latitude: 41.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 0),
      );
      final end = _snapshot(
        latitude: 41.5,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 10),
      );
      expect(
        CourierFraudSignalDetector.detectUnrealisticTravel(
          windowStart: start,
          windowEnd: end,
        ),
        CourierFraudSignalType.unrealisticTravelDistance,
      );
    });

    test('a plausible delivery-vehicle pace never triggers', () {
      final start = _snapshot(
        latitude: 41.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 0),
      );
      final end = _snapshot(
        latitude: 41.01,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 10),
      );
      expect(
        CourierFraudSignalDetector.detectUnrealisticTravel(
          windowStart: start,
          windowEnd: end,
        ),
        isNull,
      );
    });
  });

  group('CourierFraudSignalDetector.detectMockLocation', () {
    test('an isMocked reading triggers', () {
      final snapshot = _snapshot(
        capturedAt: DateTime(2026, 1, 1, 12),
        isMocked: true,
      );
      expect(
        CourierFraudSignalDetector.detectMockLocation(snapshot),
        CourierFraudSignalType.mockLocationDetected,
      );
    });

    test('a genuine reading never triggers', () {
      final snapshot = _snapshot(capturedAt: DateTime(2026, 1, 1, 12));
      expect(CourierFraudSignalDetector.detectMockLocation(snapshot), isNull);
    });
  });
}
