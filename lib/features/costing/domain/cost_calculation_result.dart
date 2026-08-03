import '../../../shared/models/money.dart';
import '../../recipes/domain/recipe_calculation_status.dart';
import 'costing_method.dart';

/// One recorded run of `CalculateRecipeCost` for a fixed
/// `recipeVersionId` — Phase 7 (`docs/decisions.md` ADR-024). Covers
/// both "RecipeCost" (batch total, [totalCost]) and "PortionCost"
/// ([perPortionCost]) from the brief in one persisted record — a
/// sub-recipe's cost has no separate record of its own, the same way
/// nutrition handles it: nested sub-recipes are flattened to raw
/// ingredients before costing, so their cost is embedded directly in
/// the ingredient-level totals.
///
/// [status] is [RecipeCalculationStatus.incomplete] whenever
/// [missingIngredientIds] is non-empty — "missing costs produce
/// incomplete-cost status, not zero." Historical order/sale records
/// are expected to copy a result's values into their own frozen
/// snapshot at sale time (a `CostSnapshot`-shaped concept) rather than
/// referencing this row live — recalculating a recipe's cost later
/// must never silently change a past sale's recorded cost. No
/// `CostSnapshot` writer exists yet this phase (no real order-time
/// integration point for costing has been wired in — see 7O for the
/// equivalent stock-consumption wiring, which costing does not yet
/// share).
class CostCalculationResult {
  const CostCalculationResult({
    required this.id,
    required this.recipeId,
    required this.recipeVersionId,
    required this.totalCost,
    required this.perPortionCost,
    required this.portionCount,
    required this.missingIngredientIds,
    required this.status,
    required this.costingMethod,
    required this.calculationRevision,
    required this.calculatedAt,
  });

  final String id;
  final String recipeId;
  final String recipeVersionId;

  /// `null` only when nothing at all could be costed (every ingredient
  /// missing) — otherwise the exact sum of every ingredient that
  /// *could* be costed (never defaulted to zero for the missing ones).
  final Money? totalCost;
  final Money? perPortionCost;
  final int portionCount;
  final List<String> missingIngredientIds;
  final RecipeCalculationStatus status;
  final CostingMethod costingMethod;
  final int calculationRevision;
  final DateTime calculatedAt;
}
