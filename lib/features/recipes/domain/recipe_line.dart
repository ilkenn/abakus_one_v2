import '../../../core/errors/business_rule_violation.dart';
import '../../inventory/domain/quantity.dart';

/// One line within a [RecipeVersion]/[SubRecipeVersion]: a quantity of
/// either a raw [Ingredient] or a nested [SubRecipe] — Phase 7
/// (`docs/decisions.md` ADR-024). Exactly one of [ingredientId]/
/// [subRecipeId] is set, never both or neither — enforced in the
/// constructor, not left to caller discipline.
class RecipeLine {
  factory RecipeLine({
    required String id,
    String? ingredientId,
    String? subRecipeId,
    required Quantity quantity,
  }) {
    final hasIngredient = ingredientId != null;
    final hasSubRecipe = subRecipeId != null;
    if (hasIngredient == hasSubRecipe) {
      throw InvalidRecipeLineViolation(
        reason: hasIngredient
            ? 'a line cannot reference both an ingredient and a sub-recipe'
            : 'a line must reference either an ingredient or a sub-recipe',
      );
    }
    return RecipeLine._(
      id: id,
      ingredientId: ingredientId,
      subRecipeId: subRecipeId,
      quantity: quantity,
    );
  }

  const RecipeLine._({
    required this.id,
    required this.ingredientId,
    required this.subRecipeId,
    required this.quantity,
  });

  final String id;
  final String? ingredientId;
  final String? subRecipeId;
  final Quantity quantity;

  bool get referencesIngredient => ingredientId != null;
  bool get referencesSubRecipe => subRecipeId != null;
}
