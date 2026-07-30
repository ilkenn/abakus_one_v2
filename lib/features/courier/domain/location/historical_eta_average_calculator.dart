import 'eta_historical_sample.dart';

/// Derives an average travel speed from completed deliveries' actual
/// distance/duration — Sprint 5B Part 5's "historical average foundation."
/// A pure, stateless calculator: callers fetch [EtaHistoricalSample]s from
/// storage themselves and pass them in — no I/O here.
abstract final class HistoricalEtaAverageCalculator {
  HistoricalEtaAverageCalculator._();

  /// Returns `null` when there are fewer than [minimumSampleCount]
  /// samples — "not enough history yet," never a guessed average.
  /// Callers fall back to a fixed assumed speed in that case.
  static double? averageSpeedMetersPerSecond({
    required List<EtaHistoricalSample> samples,
    int minimumSampleCount = 5,
  }) {
    if (samples.length < minimumSampleCount) return null;
    final totalDistance = samples.fold(0.0, (sum, s) => sum + s.distanceMeters);
    final totalSeconds =
        samples.fold(0.0, (sum, s) => sum + s.actualDurationSeconds);
    if (totalSeconds <= 0) return null;
    return totalDistance / totalSeconds;
  }
}
