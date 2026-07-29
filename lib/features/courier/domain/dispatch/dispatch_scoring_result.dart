/// One courier candidate's computed dispatch score — higher is better.
/// [breakdown] preserves each named factor's contribution, so a dispatch
/// decision can be explained/reviewed rather than being an opaque number
/// (matches the explicit "no autonomous courier scoring" boundary: this
/// ranks *delivery assignment candidates* for one delivery, never scores
/// a courier's overall performance/worth).
class DispatchScoringResult {
  const DispatchScoringResult({
    required this.courierId,
    required this.score,
    this.breakdown = const {},
    required this.isEligible,
  });

  final String courierId;
  final double score;
  final Map<String, double> breakdown;

  /// `false` if this candidate fails a hard eligibility gate (offline,
  /// suspended, no capacity, wrong branch, unsuitable vehicle) — such
  /// candidates are still returned (for visibility/debugging) but must
  /// never be offered a delivery.
  final bool isEligible;
}
