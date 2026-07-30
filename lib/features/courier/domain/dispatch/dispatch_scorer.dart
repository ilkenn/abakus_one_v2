import 'dispatch_scoring_input.dart';
import 'dispatch_scoring_result.dart';

/// Deterministic, testable, rule-based dispatch scoring — a pure function
/// (no I/O), mirroring `KitchenRoutingResolver`/`ExpeditorProjectionBuilder`'s
/// shape. **Not production route optimization** — distance is a straight-
/// line estimate, weights are simple fixed constants, not a trained model.
abstract final class DispatchScorer {
  DispatchScorer._();

  static List<DispatchScoringResult> rank(
      List<DispatchScoringInput> candidates) {
    final results = candidates.map(_score).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  static DispatchScoringResult _score(DispatchScoringInput input) {
    final isEligible = input.isAvailable &&
        input.isEligibleForBranch &&
        input.hasCapacity &&
        input.isVehicleSuitable &&
        !input.isTemporarilyBlockedFromNewPackages;

    if (!isEligible) {
      return DispatchScoringResult(
        courierId: input.courierId,
        score: 0,
        isEligible: false,
      );
    }

    // Closer is better: 0 distance -> 1.0, 5km+ -> ~0.
    final distance = input.distanceEstimateMeters ?? 2000;
    final distanceScore = (1 - (distance / 5000)).clamp(0.0, 1.0);

    // More free capacity is better.
    final capacityScore =
        1 - (input.activeDeliveryCount / input.capacity).clamp(0.0, 1.0);

    // Longer package wait -> higher urgency -> favor assigning this
    // delivery sooner (this factor rewards the *delivery's* urgency, the
    // same weight applies to every candidate for it, so it doesn't bias
    // between candidates — kept for completeness/explainability only).
    final urgencyScore = (input.packageWaitSeconds / 1200).clamp(0.0, 1.0);

    // Recent rejections lower priority slightly, never to zero.
    final reliabilityScore =
        1 - (input.recentRejectionCount * 0.15).clamp(0.0, 0.6);

    final breakdown = {
      'distance': distanceScore,
      'capacity': capacityScore,
      'urgency': urgencyScore,
      'reliability': reliabilityScore,
    };
    final score = distanceScore * 0.4 +
        capacityScore * 0.3 +
        urgencyScore * 0.1 +
        reliabilityScore * 0.2;

    return DispatchScoringResult(
      courierId: input.courierId,
      score: score,
      breakdown: breakdown,
      isEligible: true,
    );
  }
}
