import '../../inventory/domain/quantity.dart';

/// One flattened, resolved ingredient line produced by
/// `ResolveRecipeIngredientSnapshot` for a specific, fixed
/// [recipeVersionId] — Phase 7 (`docs/decisions.md` ADR-024). Nested
/// sub-recipes are already expanded down to raw ingredients by the
/// time this exists; a snapshot tied to one version always resolves
/// identically no matter how many later `RecipeVersion`s are created,
/// since it was built from — and only ever refers back to — that one
/// immutable version.
class RecipeIngredientSnapshot {
  const RecipeIngredientSnapshot({
    required this.id,
    required this.recipeId,
    required this.recipeVersionId,
    required this.ingredientId,
    required this.ingredientName,
    required this.quantity,
    required this.createdAt,
  });

  final String id;
  final String recipeId;
  final String recipeVersionId;
  final String ingredientId;
  final String ingredientName;
  final Quantity quantity;
  final DateTime createdAt;
}
