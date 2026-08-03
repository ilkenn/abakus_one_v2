import '../../../inventory/domain/quantity.dart';

/// Configures what one [BowlBuilderIngredient] selection means in
/// recipe/stock/nutrition/allergen/cost terms — Phase 7
/// (`docs/decisions.md` ADR-024). One mapping per Bowl Builder
/// ingredient (upserted by `bowlBuilderIngredientId`, see
/// `SetBowlBuilderIngredientMapping`). A Bowl Builder ingredient with
/// no mapping simply has no recipe/stock/nutrition effect yet — an
/// honest gap, not an error, since not every ingredient needs to be
/// configured before the feature is usable at all.
class BowlBuilderIngredientRecipeMapping {
  const BowlBuilderIngredientRecipeMapping({
    required this.id,
    required this.organizationId,
    required this.bowlBuilderIngredientId,
    required this.inventoryIngredientId,
    required this.quantityPerSelection,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String bowlBuilderIngredientId;
  final String inventoryIngredientId;

  /// How much of [inventoryIngredientId] one selected unit of this
  /// Bowl Builder ingredient represents — multiplied by the customer's
  /// selected quantity when resolving a dynamic bowl recipe.
  final Quantity quantityPerSelection;

  final DateTime createdAt;
  final int revision;
}
