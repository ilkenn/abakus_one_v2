import '../../recipes/domain/recipe_calculation_status.dart';
import 'nutrition_confidence.dart';
import 'nutrition_value_set.dart';

/// One recorded run of `CalculateRecipeNutrition` for a fixed
/// `recipeVersionId` — Phase 7 (`docs/decisions.md` ADR-024). Distinct
/// from a `NutritionReferenceEntry` (one ingredient's raw reference
/// data) — this is the *derived* per-recipe/per-portion total.
///
/// [totalValues] is the exact internal calculation (integer-truncated
/// once per ingredient, never accumulated float error); display code
/// is responsible for its own rounding when presenting to a user —
/// this class never bakes in a display format.
///
/// [status] is [RecipeCalculationStatus.incomplete] whenever
/// [missingIngredientIds] is non-empty — "missing data produces an
/// incomplete status, not zero." [confidence] is the lowest
/// [NutritionConfidence] among every ingredient that *did* contribute
/// (never inferred higher than the weakest link) — this is a
/// calculated estimate, not a lab-verified value, and nothing here
/// makes or implies a legal nutrition-labeling compliance claim.
class NutritionCalculationResult {
  const NutritionCalculationResult({
    required this.id,
    required this.recipeId,
    required this.recipeVersionId,
    required this.totalValues,
    required this.perPortionValues,
    required this.portionCount,
    required this.missingIngredientIds,
    required this.status,
    required this.confidence,
    required this.calculationRevision,
    required this.calculatedAt,
  });

  final String id;
  final String recipeId;
  final String recipeVersionId;
  final NutritionValueSet totalValues;
  final NutritionValueSet perPortionValues;
  final int portionCount;
  final List<String> missingIngredientIds;
  final RecipeCalculationStatus status;
  final NutritionConfidence confidence;
  final int calculationRevision;
  final DateTime calculatedAt;
}
