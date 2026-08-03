import '../../../inventory/domain/quantity.dart';
import '../../../recipes/domain/recipe_calculation_status.dart';

/// One selected Bowl Builder ingredient, as recorded on a
/// [BowlBuilderRecipeSnapshot] — the raw customer choice, before
/// mapping/scaling.
class BowlBuilderSelectionLine {
  const BowlBuilderSelectionLine({
    required this.bowlBuilderIngredientId,
    required this.quantity,
  });

  final String bowlBuilderIngredientId;
  final int quantity;
}

/// One resolved raw-ingredient effect of a bowl, as recorded on a
/// [BowlBuilderRecipeSnapshot] — after merging the (optional) base
/// recipe with every mapped selection.
class BowlBuilderResolvedIngredientLine {
  const BowlBuilderResolvedIngredientLine({
    required this.ingredientId,
    required this.quantity,
  });

  final String ingredientId;
  final Quantity quantity;
}

/// An immutable, point-in-time record of one finalized Bowl Builder
/// selection — Phase 7 (`docs/decisions.md` ADR-024). Created once, at
/// cart finalization (`CreateBowlBuilderRecipeSnapshot`), and never
/// edited afterward — "at order submission create immutable snapshot
/// of selections/quantities/... cost basis/price basis/recipe version
/// references." No `copyWith`: nothing about a snapshot is meant to
/// change after creation, including as later phases (7I/7J/7K/7M) wire
/// nutrition/allergen/cost calculation in — those write *new*
/// snapshots or a separate calculation-result record, never mutate
/// this one in place.
///
/// [nutritionStatus]/[allergenStatus]/[costStatus] start at
/// [RecipeCalculationStatus.notYetCalculated] because those engines
/// don't exist yet this phase — an honest gap, not a fabricated value.
class BowlBuilderRecipeSnapshot {
  const BowlBuilderRecipeSnapshot({
    required this.id,
    required this.contextId,
    required this.organizationId,
    this.branchId,
    this.baseRecipeId,
    this.baseRecipeVersionId,
    required this.selections,
    required this.resolvedIngredientLines,
    required this.nutritionStatus,
    required this.allergenStatus,
    required this.costStatus,
    required this.priceBasisMinorUnits,
    required this.priceBasisCurrencyCode,
    required this.createdAt,
  });

  final String id;

  /// The cart item / order line this snapshot belongs to — opaque to
  /// this feature (Bowl Builder doesn't depend on `features/cart` or
  /// `features/orders`); callers supply whatever id they already use.
  final String contextId;

  final String organizationId;
  final String? branchId;
  final String? baseRecipeId;
  final String? baseRecipeVersionId;
  final List<BowlBuilderSelectionLine> selections;
  final List<BowlBuilderResolvedIngredientLine> resolvedIngredientLines;
  final RecipeCalculationStatus nutritionStatus;
  final RecipeCalculationStatus allergenStatus;
  final RecipeCalculationStatus costStatus;
  final int priceBasisMinorUnits;
  final String priceBasisCurrencyCode;
  final DateTime createdAt;
}
