import 'cooking_loss.dart';
import 'portion_definition.dart';
import 'preparation_loss.dart';
import 'recipe_line.dart';
import 'yield.dart';

/// One immutable, numbered version of a [Recipe]'s composition — Phase
/// 7 (`docs/decisions.md` ADR-024). Editing a recipe never mutates an
/// existing [RecipeVersion]; it creates a new one and repoints
/// `Recipe.currentVersionId` at it. Every past version stays
/// retrievable forever — "editing a recipe never rewrites historical
/// costs/nutrition," because whatever referenced version a past order
/// snapshot points to still resolves exactly as it did at the time.
class RecipeVersion {
  const RecipeVersion({
    required this.id,
    required this.recipeId,
    required this.versionNumber,
    required this.lines,
    required this.portionDefinition,
    required this.yieldAmount,
    this.preparationLoss,
    this.cookingLoss,
    required this.createdAt,
    required this.createdByStaffId,
  });

  final String id;
  final String recipeId;
  final int versionNumber;
  final List<RecipeLine> lines;
  final PortionDefinition portionDefinition;

  /// Named `yieldAmount`, not `yield` — `yield` is a reserved word
  /// inside any `async`/generator function body in Dart, which would
  /// make this field's name unusable as a named-argument label from
  /// almost every use case in this codebase.
  final Yield yieldAmount;
  final PreparationLoss? preparationLoss;
  final CookingLoss? cookingLoss;
  final DateTime createdAt;
  final String createdByStaffId;
}
