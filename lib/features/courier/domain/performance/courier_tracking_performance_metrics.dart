/// Assembled GPS/sync/battery performance metrics for one courier over a
/// window — Sprint 5B Part 12. Every field is nullable: each is only
/// computable when the underlying data exists (e.g. no battery-level
/// readings yet means [batteryDrainPercentPerHour] stays `null`, never a
/// fabricated zero). Never persisted itself — always computed fresh by
/// `CourierTrackingPerformanceCalculator` from the existing repositories.
class CourierTrackingPerformanceMetrics {
  const CourierTrackingPerformanceMetrics({
    required this.courierId,
    this.averageAccuracyMeters,
    this.averageLocationLatency,
    this.averageSyncLatency,
    this.estimatedDroppedUpdateCount,
    this.reconnectCount,
    this.totalOfflineDuration,
    this.averageEtaErrorMinutes,
    this.batteryDrainPercentPerHour,
    this.trackingUptimeRatio,
  });

  final String courierId;

  /// Mean `CourierLocationSnapshot.accuracyMeters` across the window.
  final double? averageAccuracyMeters;

  /// Mean `receivedAt - capturedAt` across the window — how long a
  /// reading takes to reach the backend under normal (online) delivery.
  final Duration? averageLocationLatency;

  /// Mean `syncedAt - capturedAt` across offline-queued readings — the
  /// latency penalty specifically attributable to being offline.
  final Duration? averageSyncLatency;

  /// A gap-based estimate of updates the device likely missed, given an
  /// expected reporting interval — never an exact count (no sequence
  /// numbers exist to count against).
  final int? estimatedDroppedUpdateCount;

  /// Distinct offline-sync passes observed in the queue history — a proxy
  /// for how many times the device reconnected after being offline.
  final int? reconnectCount;

  /// Total time offline-queued readings spent waiting to sync.
  final Duration? totalOfflineDuration;

  /// Mean absolute difference between a predicted ETA and the actual
  /// checkpoint timestamp it was estimating, in minutes.
  final double? averageEtaErrorMinutes;

  /// Estimated battery percentage drained per hour, from consecutive
  /// `batteryLevelPercent` readings.
  final double? batteryDrainPercentPerHour;

  /// 0.0-1.0: the fraction of the observation window actually covered by
  /// location readings.
  final double? trackingUptimeRatio;
}
