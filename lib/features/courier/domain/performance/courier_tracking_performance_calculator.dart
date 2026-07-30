import '../location/courier_location_snapshot.dart';
import '../location/queued_courier_location.dart';

/// Pure, stateless calculators over a courier's already-stored
/// location/sync/battery data — Sprint 5B Part 12. Each metric is its own
/// independent static method (no single "compute everything" entry
/// point): mirrors `GeofenceEvaluator`/`AdaptiveTrackingPolicy`'s shape,
/// no I/O, every threshold a parameter.
abstract final class CourierTrackingPerformanceCalculator {
  CourierTrackingPerformanceCalculator._();

  static double? averageAccuracyMeters(List<CourierLocationSnapshot> history) {
    if (history.isEmpty) return null;
    final total = history.fold(0.0, (sum, s) => sum + s.accuracyMeters);
    return total / history.length;
  }

  static Duration? averageLocationLatency(
    List<CourierLocationSnapshot> history,
  ) {
    if (history.isEmpty) return null;
    final totalMicroseconds = history.fold<int>(
      0,
      (sum, s) => sum + s.receivedAt.difference(s.capturedAt).inMicroseconds,
    );
    return Duration(microseconds: totalMicroseconds ~/ history.length);
  }

  /// [expectedInterval] is the reporting cadence the caller was actually
  /// running at (e.g. `AdaptiveTrackingPolicy.intervalFor`'s result) —
  /// never a hardcoded assumption inside this calculator. A gap larger
  /// than `expectedInterval * toleranceMultiplier` counts as
  /// `round(gap / expectedInterval) - 1` likely-dropped updates.
  static int estimatedDroppedUpdates({
    required List<CourierLocationSnapshot> history,
    required Duration expectedInterval,
    double toleranceMultiplier = 2.0,
  }) {
    if (history.length < 2 || expectedInterval <= Duration.zero) return 0;
    final sorted = [...history]
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

    var dropped = 0;
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i].capturedAt.difference(sorted[i - 1].capturedAt);
      if (gap > expectedInterval * toleranceMultiplier) {
        final missed =
            (gap.inMilliseconds / expectedInterval.inMilliseconds).round() - 1;
        if (missed > 0) dropped += missed;
      }
    }
    return dropped;
  }

  /// From the first and last readings with a non-null
  /// `batteryLevelPercent` — `null` when fewer than two such readings
  /// exist, or when the level never decreased (a charging device isn't a
  /// meaningful "drain rate").
  static double? batteryDrainPercentPerHour(
    List<CourierLocationSnapshot> history,
  ) {
    final withBattery = history
        .where((s) => s.batteryLevelPercent != null)
        .toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    if (withBattery.length < 2) return null;

    final first = withBattery.first;
    final last = withBattery.last;
    final drained = first.batteryLevelPercent! - last.batteryLevelPercent!;
    if (drained <= 0) return null;

    final hours = last.capturedAt.difference(first.capturedAt).inMinutes / 60.0;
    if (hours <= 0) return null;
    return drained / hours;
  }

  /// The fraction of `[windowStart, windowEnd]` actually spanned by
  /// location readings — a coarse coverage signal, not a precise duty
  /// cycle (it does not account for [expectedInterval] gaps within the
  /// span; combine with [estimatedDroppedUpdates] for that).
  static double trackingUptimeRatio({
    required List<CourierLocationSnapshot> history,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    final windowDuration = windowEnd.difference(windowStart);
    if (windowDuration <= Duration.zero) return 0;
    if (history.length < 2) return 0;

    final sorted = [...history]
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    final covered = sorted.last.capturedAt.difference(sorted.first.capturedAt);
    final ratio = covered.inMilliseconds / windowDuration.inMilliseconds;
    return ratio.clamp(0.0, 1.0);
  }

  static Duration? averageSyncLatency(List<QueuedCourierLocation> synced) {
    final withSyncTime =
        synced.where((q) => q.syncedAt != null).toList(growable: false);
    if (withSyncTime.isEmpty) return null;
    final totalMicroseconds = withSyncTime.fold<int>(
      0,
      (sum, q) =>
          sum + q.syncedAt!.difference(q.snapshot.capturedAt).inMicroseconds,
    );
    return Duration(microseconds: totalMicroseconds ~/ withSyncTime.length);
  }

  static Duration totalOfflineDuration(List<QueuedCourierLocation> synced) {
    return synced.where((q) => q.syncedAt != null).fold(
          Duration.zero,
          (sum, q) => sum + q.syncedAt!.difference(q.snapshot.capturedAt),
        );
  }

  /// Distinct `syncedAt` instants among synced entries — each successful
  /// `SyncQueuedCourierLocations` call stamps every snapshot it processes
  /// with the same `syncedAt`, so counting distinct values approximates
  /// how many separate reconnect-and-sync passes occurred.
  static int reconnectCount(List<QueuedCourierLocation> synced) {
    return synced
        .where((q) => q.syncedAt != null)
        .map((q) => q.syncedAt!)
        .toSet()
        .length;
  }

  /// [pairs] are `(predictedAt, actualAt)` — the caller derives
  /// `predictedAt` from `DeliveryRouteSnapshot.computedAt.add(Duration
  /// (minutes: etaMinutes))` and `actualAt` from whichever checkpoint the
  /// estimate was for; this calculator stays agnostic of both types.
  static double? averageEtaErrorMinutes(
    List<({DateTime predictedAt, DateTime actualAt})> pairs,
  ) {
    if (pairs.isEmpty) return null;
    final totalMinutes = pairs.fold<double>(
      0,
      (sum, p) => sum + p.actualAt.difference(p.predictedAt).inMinutes.abs(),
    );
    return totalMinutes / pairs.length;
  }
}
