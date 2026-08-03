import 'package:abakus_one_v2/features/bowl_builder/application/identity/bowl_builder_recipe_snapshot_id_generator.dart';
import 'package:abakus_one_v2/features/bowl_builder/application/use_cases/create_bowl_builder_recipe_snapshot.dart';
import 'package:abakus_one_v2/features/bowl_builder/application/use_cases/resolve_dynamic_bowl_recipe.dart';
import 'package:abakus_one_v2/features/bowl_builder/data/bowl_builder_ingredient_recipe_mapping_repository.dart';
import 'package:abakus_one_v2/features/bowl_builder/data/bowl_builder_recipe_snapshot_repository.dart';
import 'package:abakus_one_v2/features/bowl_builder/domain/models/bowl_builder_ingredient_recipe_mapping.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_version_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/sub_recipe_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/sub_recipe_version_repository.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_calculation_status.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_line_flattener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreateBowlBuilderRecipeSnapshot', () {
    test('persists an immutable snapshot with notYetCalculated statuses',
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
      final resolver = ResolveDynamicBowlRecipe(
        recipeRepository: InMemoryRecipeRepository(),
        recipeVersionRepository: InMemoryRecipeVersionRepository(),
        mappingRepository: mappingRepository,
        flattener: RecipeLineFlattener(
          subRecipeRepository: InMemorySubRecipeRepository(),
          subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        ),
      );
      final snapshotRepository = InMemoryBowlBuilderRecipeSnapshotRepository();
      final useCase = CreateBowlBuilderRecipeSnapshot(
        idGenerator: SequentialBowlBuilderRecipeSnapshotIdGenerator(),
        resolver: resolver,
        repository: snapshotRepository,
      );

      final snapshot = await useCase(
        contextId: 'custom_bowl_123',
        organizationId: 'org-1',
        branchId: 'branch-1',
        selections: {'chicken': 2},
        priceBasisMinorUnits: 4500,
        priceBasisCurrencyCode: 'TRY',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(snapshot.contextId, 'custom_bowl_123');
      expect(snapshot.selections, hasLength(1));
      expect(snapshot.selections.single.quantity, 2);
      expect(snapshot.resolvedIngredientLines, hasLength(1));
      expect(
          snapshot.resolvedIngredientLines.single.quantity.smallestUnits, 100);
      expect(
          snapshot.nutritionStatus, RecipeCalculationStatus.notYetCalculated);
      expect(snapshot.allergenStatus, RecipeCalculationStatus.notYetCalculated);
      expect(snapshot.costStatus, RecipeCalculationStatus.notYetCalculated);
      expect(snapshot.priceBasisMinorUnits, 4500);

      final persisted =
          await snapshotRepository.findByContextId('custom_bowl_123');
      expect(persisted, hasLength(1));
      expect(persisted.single.id, snapshot.id);
    });

    test('a zero-quantity selection is excluded from the recorded selections',
        () async {
      final resolver = ResolveDynamicBowlRecipe(
        recipeRepository: InMemoryRecipeRepository(),
        recipeVersionRepository: InMemoryRecipeVersionRepository(),
        mappingRepository:
            InMemoryBowlBuilderIngredientRecipeMappingRepository(),
        flattener: RecipeLineFlattener(
          subRecipeRepository: InMemorySubRecipeRepository(),
          subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        ),
      );
      final useCase = CreateBowlBuilderRecipeSnapshot(
        idGenerator: SequentialBowlBuilderRecipeSnapshotIdGenerator(),
        resolver: resolver,
        repository: InMemoryBowlBuilderRecipeSnapshotRepository(),
      );

      final snapshot = await useCase(
        contextId: 'custom_bowl_456',
        organizationId: 'org-1',
        selections: {'never-selected': 0},
        priceBasisMinorUnits: 0,
        priceBasisCurrencyCode: 'TRY',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(snapshot.selections, isEmpty);
      expect(snapshot.resolvedIngredientLines, isEmpty);
    });
  });
}
