import 'cooking_loss.dart';
import 'preparation_loss.dart';
import 'recipe_line.dart';
import 'yield.dart';

/// One immutable, numbered version of a [SubRecipe]'s composition —
/// Phase 7 (`docs/decisions.md` ADR-024). Same immutable-version
/// contract as [RecipeVersion]. Has no [PortionDefinition] of its own
/// — a sub-recipe is consumed by quantity from its [yieldAmount], not
/// served directly to a customer as a portion.
class SubRecipeVersion {
  const SubRecipeVersion({
    required this.id,
    required this.subRecipeId,
    required this.versionNumber,
    required this.lines,
    required this.yieldAmount,
    this.preparationLoss,
    this.cookingLoss,
    required this.createdAt,
    required this.createdByStaffId,
  });

  final String id;
  final String subRecipeId;
  final int versionNumber;
  final List<RecipeLine> lines;

  /// See `RecipeVersion.yieldAmount`'s doc comment for why this isn't
  /// named `yield`.
  final Yield yieldAmount;
  final PreparationLoss? preparationLoss;
  final CookingLoss? cookingLoss;
  final DateTime createdAt;
  final String createdByStaffId;
}
