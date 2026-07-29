/// The outcome of evaluating a [CourierLocationSnapshot] against a target
/// point/radius — **never authoritative on its own**: a `false`
/// [isWithin] (or insufficient accuracy) blocks the relevant delivery
/// action *unless* a `GeofenceOverride` exists.
class GeofenceEvaluationResult {
  const GeofenceEvaluationResult({
    required this.isWithin,
    required this.distanceMeters,
    required this.isAccuracySufficient,
  });

  final bool isWithin;
  final double distanceMeters;

  /// `false` when the snapshot's `accuracyMeters` is too coarse to trust
  /// this evaluation at all — a low-accuracy reading is never treated as
  /// definitive evidence, per the explicit rule.
  final bool isAccuracySufficient;

  /// A geofence action is only safely automatic when both conditions hold
  /// — otherwise a manager override is required.
  bool get passesAutomatically => isWithin && isAccuracySufficient;
}
