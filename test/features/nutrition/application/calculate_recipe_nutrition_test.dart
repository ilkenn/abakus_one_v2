import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/nutrition/application/identity/nutrition_calculation_result_id_generator.dart';
import 'package:abakus_one_v2/features/nutrition/application/use_cases/calculate_recipe_nutrition.dart';
import 'package:abakus_one_v2/features/nutrition/data/nutrition_calculation_result_repository.dart';
import 'package:abakus_one_v2/features/nutrition/data/nutrition_reference_entry_repository.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_confidence.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_data_source_type.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_reference_entry.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_value_set.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_version_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/sub_recipe_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/sub_recipe_version_repository.dart';
import 'package:abakus_one_v2/features/recipes/domain/portion_definition.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_calculation_status.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_line.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_version.dart';
import 'package:abakus_one_v2/features/recipes/domain/yield.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../recipes/test_support/recipe_test_fixtures.dart';

Future<Recipe> _seedRecipe({
  required RecipeRepository recipeRepository,
  required RecipeVersionRepository versionRepository,
  required int portionCount,
}) async {
  final version = RecipeVersion(
    id: 'version-1',
    recipeId: 'recipe-1',
    versionNumber: 1,
    lines: [
      RecipeLine(
        id: 'line-1',
        ingredientId: 'chicken',
        quantity: Quantity.fromWhole(200, InventoryUnit.gram),
      ),
      RecipeLine(
        id: 'line-2',
        ingredientId: 'unknown-ingredient',
        quantity: Quantity.fromWhole(50, InventoryUnit.gram),
      ),
    ],
    portionDefinition: PortionDefinition(
      quantity: Quantity.fromWhole(1, InventoryUnit.portion),
    ),
    yieldAmount: Yield(
      totalQuantity: Quantity.fromWhole(250, InventoryUnit.gram),
      portionCount: portionCount,
    ),
    createdAt: DateTime(2026, 1, 1),
    createdByStaffId: 'manager-1',
  );
  await versionRepository.save(version);
  final recipe = Recipe(
    id: 'recipe-1',
    organizationId: 'org-1',
    name: 'Tavuklu Bowl',
    currentVersionId: version.id,
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
  await recipeRepository.save(recipe);
  return recipe;
}

void main() {
  group('CalculateRecipeNutrition', () {
    test(
        'flattens the recipe, sums known ingredients and flags the '
        'unknown one as missing (incomplete status)', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
      await _seedRecipe(
        recipeRepository: recipeRepository,
        versionRepository: versionRepository,
        portionCount: 2,
      );

      final referenceRepository = InMemoryNutritionReferenceEntryRepository();
      await referenceRepository.save(NutritionReferenceEntry(
        id: 'chicken-entry',
        organizationId: 'org-1',
        ingredientId: 'chicken',
        values: const NutritionValueSet(
          energyKcal: 165,
          proteinMilligrams: 31000,
          carbohydrateMilligrams: 0,
          fatMilligrams: 3600,
          saturatedFatMilligrams: 1000,
          fiberMilligrams: 0,
          sugarMilligrams: 0,
          saltMilligrams: 74,
          sodiumMilligrams: 74,
        ),
        referenceUnit: InventoryUnit.gram,
        sourceType: NutritionDataSourceType.externalProvider,
        confidence: NutritionConfidence.medium,
        isManuallyOverridden: false,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final useCase = CalculateRecipeNutrition(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialNutritionCalculationResultIdGenerator(),
        recipeRepository: recipeRepository,
        recipeVersionRepository: versionRepository,
        subRecipeRepository: InMemorySubRecipeRepository(),
        subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        referenceEntryRepository: referenceRepository,
        resultRepository: InMemoryNutritionCalculationResultRepository(),
      );

      final result = await useCase(
        recipeId: 'recipe-1',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      // 200g chicken = 2x the 100g reference.
      expect(result.totalValues.energyKcal, 330);
      expect(result.totalValues.proteinMilligrams, 62000);
      expect(result.missingIngredientIds, ['unknown-ingredient']);
      expect(result.status, RecipeCalculationStatus.incomplete);
      // 2 portions -> per-portion is half of the total.
      expect(result.perPortionValues.energyKcal, 165);
      expect(result.calculationRevision, 1);
    });

    test('recalculating the same version increments calculationRevision',
        () async {
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
      await _seedRecipe(
        recipeRepository: recipeRepository,
        versionRepository: versionRepository,
        portionCount: 1,
      );
      final resultRepository = InMemoryNutritionCalculationResultRepository();
      final useCase = CalculateRecipeNutrition(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialNutritionCalculationResultIdGenerator(),
        recipeRepository: recipeRepository,
        recipeVersionRepository: versionRepository,
        subRecipeRepository: InMemorySubRecipeRepository(),
        subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        referenceEntryRepository: InMemoryNutritionReferenceEntryRepository(),
        resultRepository: resultRepository,
      );

      final first = await useCase(
        recipeId: 'recipe-1',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );
      final second = await useCase(
        recipeId: 'recipe-1',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 3),
      );

      expect(first.calculationRevision, 1);
      expect(second.calculationRevision, 2);
    });

    test('an unauthorized actor is denied', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
      await _seedRecipe(
        recipeRepository: recipeRepository,
        versionRepository: versionRepository,
        portionCount: 1,
      );
      final useCase = CalculateRecipeNutrition(
        authorizationPolicy: const DenyAllRecipesPolicy(),
        idGenerator: SequentialNutritionCalculationResultIdGenerator(),
        recipeRepository: recipeRepository,
        recipeVersionRepository: versionRepository,
        subRecipeRepository: InMemorySubRecipeRepository(),
        subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        referenceEntryRepository: InMemoryNutritionReferenceEntryRepository(),
        resultRepository: InMemoryNutritionCalculationResultRepository(),
      );

      expect(
        () => useCase(
          recipeId: 'recipe-1',
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 2),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
