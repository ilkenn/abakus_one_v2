import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:abakus_one_v2/features/courier/domain/location/queued_courier_location.dart';
import 'package:abakus_one_v2/features/courier/domain/location/queued_location_sync_status.dart';
import 'package:abakus_one_v2/features/courier/domain/performance/courier_tracking_performance_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

CourierLocationSnapshot _snapshot({
  double accuracyMeters = 10,
  required DateTime capturedAt,
  DateTime? receivedAt,
  int? batteryLevelPercent,
}) {
  return CourierLocationSnapshot(
    id: 'loc-1',
    courierId: 'courier-1',
    deviceId: 'device-1',
    latitude: 41.0,
    longitude: 29.0,
    accuracyMeters: accuracyMeters,
    batteryLevelPercent: batteryLevelPercent,
    capturedAt: capturedAt,
    receivedAt: receivedAt ?? capturedAt,
  );
}

void main() {
  group('CourierTrackingPerformanceCalculator.averageAccuracyMeters', () {
    test('empty history returns null', () {
      expect(CourierTrackingPerformanceCalculator.averageAccuracyMeters([]),
          isNull);
    });

    test('averages accuracy across all readings', () {
      final result =
          CourierTrackingPerformanceCalculator.averageAccuracyMeters([
        _snapshot(accuracyMeters: 10, capturedAt: DateTime(2026, 1, 1)),
        _snapshot(accuracyMeters: 20, capturedAt: DateTime(2026, 1, 1, 0, 1)),
      ]);
      expect(result, 15);
    });
  });

  group('CourierTrackingPerformanceCalculator.averageLocationLatency', () {
    test('empty history returns null', () {
      expect(CourierTrackingPerformanceCalculator.averageLocationLatency([]),
          isNull);
    });

    test('averages receivedAt - capturedAt across readings', () {
      final result =
          CourierTrackingPerformanceCalculator.averageLocationLatency([
        _snapshot(
          capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
          receivedAt: DateTime(2026, 1, 1, 12, 0, 2),
        ),
        _snapshot(
          capturedAt: DateTime(2026, 1, 1, 12, 0, 10),
          receivedAt: DateTime(2026, 1, 1, 12, 0, 14),
        ),
      ]);
      expect(result, const Duration(seconds: 3));
    });
  });

  group('CourierTrackingPerformanceCalculator.estimatedDroppedUpdates', () {
    test('fewer than two readings never estimates a drop', () {
      final result =
          CourierTrackingPerformanceCalculator.estimatedDroppedUpdates(
        history: [_snapshot(capturedAt: DateTime(2026, 1, 1))],
        expectedInterval: const Duration(seconds: 10),
      );
      expect(result, 0);
    });

    test('regular readings at the expected interval estimate zero drops', () {
      final result =
          CourierTrackingPerformanceCalculator.estimatedDroppedUpdates(
        history: [
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 0, 0)),
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 0, 10)),
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 0, 20)),
        ],
        expectedInterval: const Duration(seconds: 10),
      );
      expect(result, 0);
    });

    test(
        'a gap several times the expected interval estimates the missed '
        'updates', () {
      final result =
          CourierTrackingPerformanceCalculator.estimatedDroppedUpdates(
        history: [
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 0, 0)),
          // 50s gap at a 10s expected interval -> ~4 missed updates.
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 0, 50)),
        ],
        expectedInterval: const Duration(seconds: 10),
      );
      expect(result, 4);
    });
  });

  group('CourierTrackingPerformanceCalculator.batteryDrainPercentPerHour', () {
    test('fewer than two battery readings returns null', () {
      final result =
          CourierTrackingPerformanceCalculator.batteryDrainPercentPerHour(
        [_snapshot(capturedAt: DateTime(2026, 1, 1), batteryLevelPercent: 80)],
      );
      expect(result, isNull);
    });

    test('computes drain rate from first/last battery readings', () {
      final result =
          CourierTrackingPerformanceCalculator.batteryDrainPercentPerHour([
        _snapshot(
          capturedAt: DateTime(2026, 1, 1, 12, 0),
          batteryLevelPercent: 90,
        ),
        _snapshot(
          capturedAt: DateTime(2026, 1, 1, 13, 0),
          batteryLevelPercent: 80,
        ),
      ]);
      expect(result, 10);
    });

    test(
        'a level that never decreases returns null (never a negative '
        'drain rate)', () {
      final result =
          CourierTrackingPerformanceCalculator.batteryDrainPercentPerHour([
        _snapshot(
          capturedAt: DateTime(2026, 1, 1, 12, 0),
          batteryLevelPercent: 80,
        ),
        _snapshot(
          capturedAt: DateTime(2026, 1, 1, 13, 0),
          batteryLevelPercent: 90,
        ),
      ]);
      expect(result, isNull);
    });
  });

  group('CourierTrackingPerformanceCalculator.trackingUptimeRatio', () {
    test('full coverage of the window returns 1.0', () {
      final result = CourierTrackingPerformanceCalculator.trackingUptimeRatio(
        history: [
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 0)),
          _snapshot(capturedAt: DateTime(2026, 1, 1, 13, 0)),
        ],
        windowStart: DateTime(2026, 1, 1, 12, 0),
        windowEnd: DateTime(2026, 1, 1, 13, 0),
      );
      expect(result, 1.0);
    });

    test('partial coverage returns the covered fraction', () {
      final result = CourierTrackingPerformanceCalculator.trackingUptimeRatio(
        history: [
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 0)),
          _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 30)),
        ],
        windowStart: DateTime(2026, 1, 1, 12, 0),
        windowEnd: DateTime(2026, 1, 1, 13, 0),
      );
      expect(result, 0.5);
    });

    test('fewer than two readings returns 0', () {
      final result = CourierTrackingPerformanceCalculator.trackingUptimeRatio(
        history: [_snapshot(capturedAt: DateTime(2026, 1, 1, 12, 30))],
        windowStart: DateTime(2026, 1, 1, 12, 0),
        windowEnd: DateTime(2026, 1, 1, 13, 0),
      );
      expect(result, 0);
    });
  });

  group('CourierTrackingPerformanceCalculator queue-derived metrics', () {
    QueuedCourierLocation synced({
      required DateTime capturedAt,
      required DateTime syncedAt,
    }) {
      return QueuedCourierLocation(
        snapshot: _snapshot(capturedAt: capturedAt),
        status: QueuedLocationSyncStatus.synced,
        syncedAt: syncedAt,
      );
    }

    test('averageSyncLatency averages syncedAt - capturedAt', () {
      final result = CourierTrackingPerformanceCalculator.averageSyncLatency([
        synced(
          capturedAt: DateTime(2026, 1, 1, 12, 0),
          syncedAt: DateTime(2026, 1, 1, 12, 5),
        ),
        synced(
          capturedAt: DateTime(2026, 1, 1, 12, 10),
          syncedAt: DateTime(2026, 1, 1, 12, 13),
        ),
      ]);
      expect(result, const Duration(minutes: 4));
    });

    test('averageSyncLatency with no synced entries returns null', () {
      expect(
          CourierTrackingPerformanceCalculator.averageSyncLatency([]), isNull);
    });

    test('totalOfflineDuration sums every synced entry\'s offline wait', () {
      final result = CourierTrackingPerformanceCalculator.totalOfflineDuration([
        synced(
          capturedAt: DateTime(2026, 1, 1, 12, 0),
          syncedAt: DateTime(2026, 1, 1, 12, 5),
        ),
        synced(
          capturedAt: DateTime(2026, 1, 1, 12, 10),
          syncedAt: DateTime(2026, 1, 1, 12, 12),
        ),
      ]);
      expect(result, const Duration(minutes: 7));
    });

    test('reconnectCount counts distinct syncedAt instants, not entries', () {
      final sameSyncPass = DateTime(2026, 1, 1, 12, 5);
      final result = CourierTrackingPerformanceCalculator.reconnectCount([
        synced(capturedAt: DateTime(2026, 1, 1, 12, 0), syncedAt: sameSyncPass),
        synced(capturedAt: DateTime(2026, 1, 1, 12, 1), syncedAt: sameSyncPass),
        synced(
          capturedAt: DateTime(2026, 1, 1, 12, 2),
          syncedAt: DateTime(2026, 1, 1, 12, 20),
        ),
      ]);
      expect(result, 2);
    });
  });

  group('CourierTrackingPerformanceCalculator.averageEtaErrorMinutes', () {
    test('empty pairs returns null', () {
      expect(CourierTrackingPerformanceCalculator.averageEtaErrorMinutes([]),
          isNull);
    });

    test('averages the absolute error across every pair', () {
      final result =
          CourierTrackingPerformanceCalculator.averageEtaErrorMinutes([
        (
          predictedAt: DateTime(2026, 1, 1, 12, 10),
          actualAt: DateTime(2026, 1, 1, 12, 15),
        ),
        (
          predictedAt: DateTime(2026, 1, 1, 12, 20),
          actualAt: DateTime(2026, 1, 1, 12, 15),
        ),
      ]);
      // errors: 5 minutes late, 5 minutes early -> average 5.
      expect(result, 5);
    });
  });
}
