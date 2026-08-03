import '../../inventory/domain/quantity.dart';

/// One raw-ingredient result of `RecipeLineFlattener.flatten` — Phase 7
/// (`docs/decisions.md` ADR-024). Not persisted on its own; callers
/// either persist it as a [RecipeIngredientSnapshot]
/// (`ResolveRecipeIngredientSnapshot`) or use it as a transient
/// computation input (the Dynamic Bowl Builder resolver, 7H).
class FlattenedIngredientLine {
  const FlattenedIngredientLine(this.ingredientId, this.quantity);

  final String ingredientId;
  final Quantity quantity;
}
