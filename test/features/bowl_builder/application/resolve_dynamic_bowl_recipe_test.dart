import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/bowl_builder/application/use_cases/resolve_dynamic_bowl_recipe.dart';
import 'package:abakus_one_v2/features/bowl_builder/data/bowl_builder_ingredient_recipe_mapping_repository.dart';
import 'package:abakus_one_v2/features/bowl_builder/domain/models/bowl_builder_ingredient_recipe_mapping.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_version_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/sub_recipe_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/sub_recipe_version_repository.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_line.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_line_flattener.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_version.dart';
import 'package:abakus_one_v2/features/recipes/domain/portion_definition.dart';
import 'package:abakus_one_v2/features/recipes/domain/yield.dart';
import 'package:flutter_test/flutter_test.dart';

ResolveDynamicBowlRecipe _buildResolver({
  required RecipeRepository recipeRepository,
  required RecipeVersionRepository recipeVersionRepository,
  required BowlBuilderIngredientRecipeMappingRepository mappingRepository,
}) {
  return ResolveDynamicBowlRecipe(
    recipeRepository: recipeRepository,
    recipeVersionRepository: recipeVersionRepository,
    mappingRepository: mappingRepository,
    flattener: RecipeLineFlattener(
      subRecipeRepository: InMemorySubRecipeRepository(),
      subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
    ),
  );
}

void main() {
  group('ResolveDynamicBowlRecipe', () {
    test('with no base recipe, resolves purely from mapped selections',
        () async {
      final mappingRepository =
          InMemoryBowlBuilderIngredientRecipeMappingRepository();
      await mappingRepository.save(BowlBuilderIngredientRecipeMapping(
        id: 'mapping-1',
        organizationId: 'org-1',
        bowlBuilderIngredientId: 'chicken',
        inventoryIngredientId: 'ingredient-chicken',
        quantityPerSelection: Quantity.fromWhole(50, InventoryUnit.gram),
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final resolver = _buildResolver(
        recipeRepository: InMemoryRecipeRepository(),
        recipeVersionRepository: InMemoryRecipeVersionRepository(),
        mappingRepository: mappingRepository,
      );

      final resolution = await resolver(
        selections: {'chicken': 3},
      );

      expect(resolution.resolvedLines, hasLength(1));
      expect(
          resolution.resolvedLines.single.ingredientId, 'ingredient-chicken');
      expect(resolution.resolvedLines.single.quantity.smallestUnits, 150);
    });

    test('an unmapped selection contributes nothing', () async {
      final resolver = _buildResolver(
        recipeRepository: InMemoryRecipeRepository(),
        recipeVersionRepository: InMemoryRecipeVersionRepository(),
        mappingRepository:
            InMemoryBowlBuilderIngredientRecipeMappingRepository(),
      );

      final resolution = await resolver(
        selections: {'unmapped-ingredient': 2},
      );

      expect(resolution.resolvedLines, isEmpty);
    });

    test(
        'merges the base recipe with a selection targeting the same '
        'ingredient into one summed line', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
      final realVersion = RecipeVersion(
        id: 'base-version-1',
        recipeId: 'base-recipe-1',
        versionNumber: 1,
        lines: [
          RecipeLine(
            id: 'base-line-1',
            ingredientId: 'ingredient-rice',
            quantity: Quantity.fromWhole(100, InventoryUnit.gram),
          ),
        ],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldAmount: Yield(
          totalQuantity: Quantity.fromWhole(100, InventoryUnit.gram),
          portionCount: 1,
        ),
        createdAt: DateTime(2026, 1, 1),
        createdByStaffId: 'manager-1',
      );
      await versionRepository.save(realVersion);
      await recipeRepository.save(Recipe(
        id: 'base-recipe-1',
        organizationId: 'org-1',
        name: 'Base Bowl',
        currentVersionId: realVersion.id,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final mappingRepository =
          InMemoryBowlBuilderIngredientRecipeMappingRepository();
      await mappingRepository.save(BowlBuilderIngredientRecipeMapping(
        id: 'mapping-rice',
        organizationId: 'org-1',
        bowlBuilderIngredientId: 'extra-rice',
        inventoryIngredientId: 'ingredient-rice',
        quantityPerSelection: Quantity.fromWhole(50, InventoryUnit.gram),
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final resolver = _buildResolver(
        recipeRepository: recipeRepository,
        recipeVersionRepository: versionRepository,
        mappingRepository: mappingRepository,
      );

      final resolution = await resolver(
        baseRecipeId: 'base-recipe-1',
        selections: {'extra-rice': 1},
      );

      expect(resolution.baseRecipeVersionId, 'base-version-1');
      expect(resolution.resolvedLines, hasLength(1));
      expect(resolution.resolvedLines.single.ingredientId, 'ingredient-rice');
      expect(resolution.resolvedLines.single.quantity.smallestUnits, 150);
    });

    test('mismatched units for the same resolved ingredient throws', () async {
      final mappingRepository =
          InMemoryBowlBuilderIngredientRecipeMappingRepository();
      await mappingRepository.save(BowlBuilderIngredientRecipeMapping(
        id: 'mapping-1',
        organizationId: 'org-1',
        bowlBuilderIngredientId: 'sauce-a',
        inventoryIngredientId: 'ingredient-sauce',
        quantityPerSelection: Quantity.fromWhole(10, InventoryUnit.gram),
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      await mappingRepository.save(BowlBuilderIngredientRecipeMapping(
        id: 'mapping-2',
        organizationId: 'org-1',
        bowlBuilderIngredientId: 'sauce-b',
        inventoryIngredientId: 'ingredient-sauce',
        quantityPerSelection: Quantity.fromWhole(10, InventoryUnit.milliliter),
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final resolver = _buildResolver(
        recipeRepository: InMemoryRecipeRepository(),
        recipeVersionRepository: InMemoryRecipeVersionRepository(),
        mappingRepository: mappingRepository,
      );

      expect(
        () => resolver(selections: {'sauce-a': 1, 'sauce-b': 1}),
        throwsA(isA<UnitMismatchViolation>()),
      );
    });
  });
}
