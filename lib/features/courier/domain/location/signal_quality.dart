import 'geofence_evaluator.dart';

/// A coarse, human-meaningful bucket for a location reading's
/// [CourierLocationSnapshot.accuracyMeters] — Sprint 5B Part 6 ("signal
/// quality"). Never itself used to gate a business decision (accuracy
/// meters vs. `GeofenceEvaluator.maxTrustedAccuracyMeters` remains the
/// actual gate); this is a UI/manager-facing display concern only.
enum SignalQuality { good, fair, poor }

abstract final class SignalQualityClassifier {
  SignalQualityClassifier._();

  /// [goodThresholdMeters] and [fairThresholdMeters] are constructor-style
  /// parameters (not hardcoded) so the buckets can be retuned; the fair
  /// threshold defaults to `GeofenceEvaluator.maxTrustedAccuracyMeters` —
  /// "fair" means "still trusted for geofence evaluation," "poor" means
  /// "the same reading `GeofenceEvaluator` would reject."
  static SignalQuality classify(
    double accuracyMeters, {
    double goodThresholdMeters = 20,
    double fairThresholdMeters = GeofenceEvaluator.maxTrustedAccuracyMeters,
  }) {
    if (accuracyMeters <= goodThresholdMeters) return SignalQuality.good;
    if (accuracyMeters <= fairThresholdMeters) return SignalQuality.fair;
    return SignalQuality.poor;
  }
}
