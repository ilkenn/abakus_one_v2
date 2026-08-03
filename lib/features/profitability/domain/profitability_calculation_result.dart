import '../../../shared/models/money.dart';
import '../../recipes/domain/recipe_calculation_status.dart';
import 'profitability_warning_type.dart';

/// One recorded run of `CalculateRecipeProfitability` for a fixed
/// `recipeVersionId` — Phase 7 (`docs/decisions.md` ADR-024).
///
/// Deliberately never called "net profit" anywhere in this codebase
/// — [grossContribution]/[contributionMarginBasisPoints] are
/// "Estimated Gross Contribution"/"Contribution Margin" per the
/// brief's own terminology requirement, because [ingredientCost] is
/// itself only an *estimate* (from `CostCalculationResult`) and
/// labor/overhead allocation is explicitly foundation-only (7M) —
/// nothing here is a true, fully-costed net profit figure.
///
/// [status] is [RecipeCalculationStatus.incomplete] whenever
/// [netRevenue] or a complete [ingredientCost] is missing — "known
/// cost coverage," not a computed number presented as complete when
/// it isn't. This class only covers product/recipe-level granularity
/// — order/branch/channel/campaign-level rollups the brief also asks
/// for are a natural aggregation on top of many of these per-recipe
/// results, not built as separate persisted types this phase (an
/// honest scope boundary, not a silent omission).
class ProfitabilityCalculationResult {
  const ProfitabilityCalculationResult({
    required this.id,
    required this.recipeId,
    required this.recipeVersionId,
    this.netRevenue,
    this.ingredientCost,
    this.packagingCost,
    this.channelCost,
    this.grossContribution,
    this.contributionMarginBasisPoints,
    required this.status,
    required this.warnings,
    required this.calculationRevision,
    required this.calculatedAt,
  });

  final String id;
  final String recipeId;
  final String recipeVersionId;
  final Money? netRevenue;
  final Money? ingredientCost;
  final Money? packagingCost;
  final Money? channelCost;
  final Money? grossContribution;

  /// 10000 = 100%.
  final int? contributionMarginBasisPoints;

  final RecipeCalculationStatus status;
  final List<ProfitabilityWarningType> warnings;
  final int calculationRevision;
  final DateTime calculatedAt;
}
