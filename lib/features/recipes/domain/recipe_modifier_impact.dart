import '../../inventory/domain/quantity.dart';

/// How selecting one modifier option changes a [Recipe]'s effective
/// ingredient quantities — Phase 7 (`docs/decisions.md` ADR-024). The
/// domain shape only; Dynamic Bowl Builder actually applies these at
/// order time (see 7H / `docs/decisions.md` for the Bowl Builder
/// integration record). [quantityDelta] is added to (or, if negative,
/// subtracted from) the recipe's existing line for
/// [targetIngredientId] — a positive delta with no existing line adds
/// a new one; this is evaluated by the 7H application service, not
/// here.
class RecipeModifierImpact {
  const RecipeModifierImpact({
    required this.id,
    required this.recipeId,
    required this.modifierGroupId,
    required this.modifierOptionId,
    required this.targetIngredientId,
    required this.quantityDelta,
    this.description,
  });

  final String id;
  final String recipeId;
  final String modifierGroupId;
  final String modifierOptionId;
  final String targetIngredientId;
  final Quantity quantityDelta;
  final String? description;
}
