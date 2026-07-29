import 'geofence_evaluation_result.dart';
import 'geofence_transition_type.dart';

/// Determines whether a courier's geofence state genuinely changed between
/// two consecutive evaluations of the same zone — Sprint 5B Part 4
/// ("entry/exit," "false-positive rejection").
///
/// **False-positive rejection is structural, not a tunable threshold**:
/// a transition is only ever reported when (a) the *current* reading's
/// accuracy is trusted (never derived from a low-accuracy point — same
/// rule [GeofenceEvaluator] already enforces) and (b) there is a real
/// previous evaluation to compare against whose `isWithin` state actually
/// differs from the current one. A single ungrounded reading — no prior
/// state to compare against — can never fabricate an "exited" event, and
/// a reading that doesn't change the zone's in/out state produces no
/// event at all (no duplicate "still inside" spam).
///
/// This does not attempt multi-point debounce of a single noisy "entered"
/// blip (e.g. three consecutive confirmations before firing) — the
/// existing codebase's evidentiary philosophy is accuracy-gates-trust,
/// not consecutive-point-counting (see `FirstVerifiedGeofenceArrivalFinder`,
/// which accepts a single accurate in-radius point as sufficient). A
/// stronger debounce is a legitimate future enhancement, not implemented
/// here — flagged as technical debt in the Sprint 5B report, not silently
/// assumed unnecessary.
abstract final class GeofenceTransitionDetector {
  GeofenceTransitionDetector._();

  /// [previous] is `null` when this is the first evaluation on record for
  /// this delivery+zone — establishes the baseline only, never itself a
  /// transition.
  static GeofenceTransitionType? detect({
    required GeofenceEvaluationResult? previous,
    required GeofenceEvaluationResult current,
  }) {
    if (!current.isAccuracySufficient) return null;
    if (previous == null) {
      return current.isWithin ? GeofenceTransitionType.entered : null;
    }
    if (previous.isWithin == current.isWithin) return null;
    return current.isWithin
        ? GeofenceTransitionType.entered
        : GeofenceTransitionType.exited;
  }
}
