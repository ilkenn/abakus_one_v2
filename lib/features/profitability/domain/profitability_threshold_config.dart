/// Branch-scoped, admin-configured warning thresholds for
/// `CalculateRecipeProfitability` — Phase 7 (`docs/decisions.md`
/// ADR-024). Any threshold left `null` simply disables the
/// corresponding warning check for that branch — never a fabricated
/// default.
class ProfitabilityThresholdConfig {
  const ProfitabilityThresholdConfig({
    required this.id,
    required this.organizationId,
    required this.branchId,
    this.lowMarginBasisPointsThreshold,
    this.costSpikeBasisPointsThreshold,
    this.floorPriceMinorUnits,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String branchId;

  /// A contribution margin below this (basis points, 10000 = 100%)
  /// triggers [ProfitabilityWarningType.lowMargin].
  final int? lowMarginBasisPointsThreshold;

  /// An ingredient-cost increase (vs. the previous calculation for the
  /// same recipe) exceeding this (basis points) triggers
  /// [ProfitabilityWarningType.costSpike].
  final int? costSpikeBasisPointsThreshold;

  /// A selling price at or below this triggers
  /// [ProfitabilityWarningType.belowFloorSelling].
  final int? floorPriceMinorUnits;

  final DateTime createdAt;
  final int revision;
}
