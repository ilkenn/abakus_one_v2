/// A caveat surfaced alongside a [ProfitabilityCalculationResult] —
/// Phase 7 (`docs/decisions.md` ADR-024). Never suppressed by default;
/// a manager reading a profitability figure must see why it might be
/// unreliable.
enum ProfitabilityWarningType {
  /// No selling price was supplied — no revenue figure to compute
  /// against at all.
  missingPrice,

  /// Contribution margin fell below the branch's configured floor.
  lowMargin,

  /// The ingredient cost jumped compared to the previous calculation
  /// for this recipe by more than the configured threshold.
  costSpike,

  /// The selling price itself fell below the branch's configured
  /// floor price — a pricing mistake more than a margin problem.
  belowFloorSelling,
}
