/// A confidence measurement derived from **counted evidence**, never a
/// fabricated percentage — Phase 7 (`docs/decisions.md` ADR-024). "Do
/// not display fabricated percentages. Confidence must be based on
/// explicit evidence and rule outputs." [score] is a pure function of
/// [satisfiedEvidenceCount]/[totalEvidenceCount] — there is no other way
/// to construct a non-zero score, so a caller can never invent one.
class ImportConfidence {
  const ImportConfidence({
    required this.satisfiedEvidenceCount,
    required this.totalEvidenceCount,
    this.reasons = const [],
  })  : assert(satisfiedEvidenceCount <= totalEvidenceCount),
        assert(satisfiedEvidenceCount >= 0),
        assert(totalEvidenceCount > 0);

  /// How many of [totalEvidenceCount] deterministic rule checks passed
  /// (e.g. "has a name," "has a numeric price," "category matched an
  /// existing one," "no duplicate found").
  final int satisfiedEvidenceCount;

  final int totalEvidenceCount;

  /// Human-readable evidence labels, one per check considered — the
  /// "explicit evidence" the score must be traceable to, always shown
  /// alongside [score] in the review UI, never the number alone.
  final List<String> reasons;

  /// Integer percentage, `0`-`100`.
  int get score => (satisfiedEvidenceCount * 100 / totalEvidenceCount).round();

  bool get isLowConfidence => score < 60;
}
