import '../../../../core/errors/business_rule_violation.dart';
import '../../../inventory/domain/quantity.dart';
import '../../../recipes/data/recipe_repository.dart';
import '../../../recipes/data/recipe_version_repository.dart';
import '../../../recipes/domain/flattened_ingredient_line.dart';
import '../../../recipes/domain/recipe_line_flattener.dart';
import '../../data/bowl_builder_ingredient_recipe_mapping_repository.dart';
import '../../domain/models/dynamic_bowl_recipe_resolution.dart';

/// Deterministically computes what one Bowl Builder selection means in
/// raw-ingredient terms — Phase 7 (`docs/decisions.md` ADR-024). Pure
/// computation: never persists anything, never checks authorization
/// (Bowl Builder is customer-facing with no staff session concept —
/// see `CreateBowlBuilderRecipeSnapshot`'s doc comment for why this
/// layer stays unauthenticated by design, not by oversight).
///
/// Starts from an optional base "bowl shell" [Recipe]'s current,
/// flattened lines (via [RecipeLineFlattener] — same nested
/// sub-recipe expansion `ResolveRecipeIngredientSnapshot` uses), then
/// adds each selected Bowl Builder ingredient's mapped effect
/// (`quantityPerSelection * selectedQuantity`). A Bowl Builder
/// ingredient with no configured mapping contributes nothing — an
/// honest gap, not an error (`SetBowlBuilderIngredientMapping` may not
/// have been run for every ingredient yet). Lines for the same
/// resolved ingredient are summed (never presented as two separate
/// lines for one ingredient).
class ResolveDynamicBowlRecipe {
  ResolveDynamicBowlRecipe({
    required RecipeRepository recipeRepository,
    required RecipeVersionRepository recipeVersionRepository,
    required BowlBuilderIngredientRecipeMappingRepository mappingRepository,
    required RecipeLineFlattener flattener,
  })  : _recipeRepository = recipeRepository,
        _recipeVersionRepository = recipeVersionRepository,
        _mappingRepository = mappingRepository,
        _flattener = flattener;

  final RecipeRepository _recipeRepository;
  final RecipeVersionRepository _recipeVersionRepository;
  final BowlBuilderIngredientRecipeMappingRepository _mappingRepository;
  final RecipeLineFlattener _flattener;

  Future<DynamicBowlRecipeResolution> call({
    String? baseRecipeId,
    required Map<String, int> selections,
  }) async {
    var baseLines = const <FlattenedIngredientLine>[];
    String? baseRecipeVersionId;

    if (baseRecipeId != null) {
      final recipe = await _recipeRepository.findById(baseRecipeId);
      if (recipe == null) {
        throw UnknownRecipeEntityViolation(
          entityName: 'Recipe',
          id: baseRecipeId,
        );
      }
      final version =
          await _recipeVersionRepository.findById(recipe.currentVersionId);
      if (version == null) {
        throw UnknownRecipeEntityViolation(
          entityName: 'RecipeVersion',
          id: recipe.currentVersionId,
        );
      }
      baseRecipeVersionId = version.id;
      baseLines = await _flattener.flatten(version.lines);
    }

    final selectionLines = <FlattenedIngredientLine>[];
    for (final entry in selections.entries) {
      if (entry.value <= 0) continue;
      final mapping =
          await _mappingRepository.findByBowlBuilderIngredientId(entry.key);
      if (mapping == null) continue;
      selectionLines.add(FlattenedIngredientLine(
        mapping.inventoryIngredientId,
        mapping.quantityPerSelection * entry.value,
      ));
    }

    return DynamicBowlRecipeResolution(
      baseRecipeVersionId: baseRecipeVersionId,
      resolvedLines: _merge([...baseLines, ...selectionLines]),
    );
  }

  List<FlattenedIngredientLine> _merge(List<FlattenedIngredientLine> lines) {
    final byIngredient = <String, Quantity>{};
    for (final line in lines) {
      final existing = byIngredient[line.ingredientId];
      if (existing == null) {
        byIngredient[line.ingredientId] = line.quantity;
        continue;
      }
      if (existing.unit != line.quantity.unit) {
        throw UnitMismatchViolation(
          expectedUnitCode: existing.unit.code,
          actualUnitCode: line.quantity.unit.code,
        );
      }
      byIngredient[line.ingredientId] = existing + line.quantity;
    }
    return [
      for (final entry in byIngredient.entries)
        FlattenedIngredientLine(entry.key, entry.value),
    ];
  }
}
