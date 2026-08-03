import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/inventory/data/ingredient_repository.dart';
import 'package:abakus_one_v2/features/inventory/domain/ingredient.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/recipes/application/identity/recipe_id_generator.dart';
import 'package:abakus_one_v2/features/recipes/application/identity/recipe_ingredient_snapshot_id_generator.dart';
import 'package:abakus_one_v2/features/recipes/application/identity/recipe_version_id_generator.dart';
import 'package:abakus_one_v2/features/recipes/application/identity/sub_recipe_id_generator.dart';
import 'package:abakus_one_v2/features/recipes/application/identity/sub_recipe_version_id_generator.dart';
import 'package:abakus_one_v2/features/recipes/application/use_cases/create_recipe.dart';
import 'package:abakus_one_v2/features/recipes/application/use_cases/create_sub_recipe.dart';
import 'package:abakus_one_v2/features/recipes/application/use_cases/resolve_recipe_ingredient_snapshot.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_ingredient_snapshot_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_version_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/sub_recipe_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/sub_recipe_version_repository.dart';
import 'package:abakus_one_v2/features/recipes/domain/portion_definition.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_line.dart';
import 'package:abakus_one_v2/features/recipes/domain/sub_recipe.dart';
import 'package:abakus_one_v2/features/recipes/domain/sub_recipe_version.dart';
import 'package:abakus_one_v2/features/recipes/domain/yield.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/recipe_test_fixtures.dart';

void main() {
  group('ResolveRecipeIngredientSnapshot', () {
    test('flattens a direct ingredient line as-is', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
      final ingredientRepository = InMemoryIngredientRepository();
      await ingredientRepository.save(Ingredient(
        id: 'ingredient-1',
        organizationId: 'org-1',
        name: 'Tavuk Göğsü',
        baseUnit: InventoryUnit.gram,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final createRecipe = CreateRecipe(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialRecipeIdGenerator(),
        versionIdGenerator: SequentialRecipeVersionIdGenerator(),
        repository: recipeRepository,
        versionRepository: versionRepository,
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );
      final recipe = await createRecipe(
        organizationId: 'org-1',
        name: 'Tavuklu Bowl',
        lines: [
          RecipeLine(
            id: 'line-1',
            ingredientId: 'ingredient-1',
            quantity: Quantity.fromWhole(150, InventoryUnit.gram),
          ),
        ],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldInfo: Yield(
          totalQuantity: Quantity.fromWhole(150, InventoryUnit.gram),
          portionCount: 1,
        ),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final useCase = ResolveRecipeIngredientSnapshot(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialRecipeIngredientSnapshotIdGenerator(),
        recipeRepository: recipeRepository,
        recipeVersionRepository: versionRepository,
        subRecipeRepository: InMemorySubRecipeRepository(),
        subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        ingredientRepository: ingredientRepository,
        snapshotRepository: InMemoryRecipeIngredientSnapshotRepository(),
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );

      final snapshots = await useCase(
        recipeId: recipe.id,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(snapshots, hasLength(1));
      expect(snapshots.single.ingredientId, 'ingredient-1');
      expect(snapshots.single.ingredientName, 'Tavuk Göğsü');
      expect(snapshots.single.quantity.smallestUnits, 150);
    });

    test('scales a nested sub-recipe line proportionally to its yield',
        () async {
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
      final subRecipeRepository = InMemorySubRecipeRepository();
      final subRecipeVersionRepository = InMemorySubRecipeVersionRepository();
      final ingredientRepository = InMemoryIngredientRepository();
      await ingredientRepository.save(Ingredient(
        id: 'tomato',
        organizationId: 'org-1',
        name: 'Domates',
        baseUnit: InventoryUnit.gram,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      // Sub-recipe "Domates Sos": 1000g total yield, made from 1000g
      // tomato (1:1 for simplicity).
      final createSubRecipe = CreateSubRecipe(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialSubRecipeIdGenerator(),
        versionIdGenerator: SequentialSubRecipeVersionIdGenerator(),
        repository: subRecipeRepository,
        versionRepository: subRecipeVersionRepository,
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );
      final subRecipe = await createSubRecipe(
        organizationId: 'org-1',
        name: 'Domates Sos',
        lines: [
          RecipeLine(
            id: 'sub-line-1',
            ingredientId: 'tomato',
            quantity: Quantity.fromWhole(1000, InventoryUnit.gram),
          ),
        ],
        yieldInfo: Yield(
          totalQuantity: Quantity.fromWhole(1000, InventoryUnit.gram),
          portionCount: 10,
        ),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      // Recipe uses 100g of the 1000g-yielding sub-recipe -> expects
      // 100g of tomato in the flattened snapshot (1/10th).
      final createRecipe = CreateRecipe(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialRecipeIdGenerator(),
        versionIdGenerator: SequentialRecipeVersionIdGenerator(),
        repository: recipeRepository,
        versionRepository: versionRepository,
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );
      final recipe = await createRecipe(
        organizationId: 'org-1',
        name: 'Sos Bowl',
        lines: [
          RecipeLine(
            id: 'line-1',
            subRecipeId: subRecipe.id,
            quantity: Quantity.fromWhole(100, InventoryUnit.gram),
          ),
        ],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldInfo: Yield(
          totalQuantity: Quantity.fromWhole(100, InventoryUnit.gram),
          portionCount: 1,
        ),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final useCase = ResolveRecipeIngredientSnapshot(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialRecipeIngredientSnapshotIdGenerator(),
        recipeRepository: recipeRepository,
        recipeVersionRepository: versionRepository,
        subRecipeRepository: subRecipeRepository,
        subRecipeVersionRepository: subRecipeVersionRepository,
        ingredientRepository: ingredientRepository,
        snapshotRepository: InMemoryRecipeIngredientSnapshotRepository(),
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );

      final snapshots = await useCase(
        recipeId: recipe.id,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(snapshots, hasLength(1));
      expect(snapshots.single.ingredientId, 'tomato');
      expect(snapshots.single.quantity.smallestUnits, 100);
    });

    test('a sub-recipe that references itself throws RecipeCycleDetected',
        () async {
      final subRecipeRepository = InMemorySubRecipeRepository();
      final subRecipeVersionRepository = InMemorySubRecipeVersionRepository();
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();

      // Manually construct a self-referencing sub-recipe (the use case
      // that builds one validly would never allow this) to exercise
      // the cycle guard directly.
      const subRecipeId = 'sub-recipe-cyclic';
      const subRecipeVersionId = 'sub-recipe-cyclic-v1';
      await subRecipeVersionRepository.save(SubRecipeVersion(
        id: subRecipeVersionId,
        subRecipeId: subRecipeId,
        versionNumber: 1,
        lines: [
          RecipeLine(
            id: 'cyclic-line',
            subRecipeId: subRecipeId,
            quantity: Quantity.fromWhole(50, InventoryUnit.gram),
          ),
        ],
        yieldAmount: Yield(
          totalQuantity: Quantity.fromWhole(100, InventoryUnit.gram),
          portionCount: 1,
        ),
        createdAt: DateTime(2026, 1, 1),
        createdByStaffId: 'manager-1',
      ));
      await subRecipeRepository.save(SubRecipe(
        id: subRecipeId,
        organizationId: 'org-1',
        name: 'Cyclic Sub-Recipe',
        currentVersionId: subRecipeVersionId,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final createRecipe = CreateRecipe(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialRecipeIdGenerator(),
        versionIdGenerator: SequentialRecipeVersionIdGenerator(),
        repository: recipeRepository,
        versionRepository: versionRepository,
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );
      final recipe = await createRecipe(
        organizationId: 'org-1',
        name: 'Broken Bowl',
        lines: [
          RecipeLine(
            id: 'line-1',
            subRecipeId: subRecipeId,
            quantity: Quantity.fromWhole(50, InventoryUnit.gram),
          ),
        ],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldInfo: Yield(
          totalQuantity: Quantity.fromWhole(50, InventoryUnit.gram),
          portionCount: 1,
        ),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final useCase = ResolveRecipeIngredientSnapshot(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialRecipeIngredientSnapshotIdGenerator(),
        recipeRepository: recipeRepository,
        recipeVersionRepository: versionRepository,
        subRecipeRepository: subRecipeRepository,
        subRecipeVersionRepository: subRecipeVersionRepository,
        ingredientRepository: InMemoryIngredientRepository(),
        snapshotRepository: InMemoryRecipeIngredientSnapshotRepository(),
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );

      expect(
        () => useCase(
          recipeId: recipe.id,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 2),
        ),
        throwsA(isA<RecipeCycleDetectedViolation>()),
      );
    });
  });
}
