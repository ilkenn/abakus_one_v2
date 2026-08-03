import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/recipes/application/identity/recipe_id_generator.dart';
import 'package:abakus_one_v2/features/recipes/application/identity/recipe_version_id_generator.dart';
import 'package:abakus_one_v2/features/recipes/application/use_cases/create_recipe.dart';
import 'package:abakus_one_v2/features/recipes/application/use_cases/create_recipe_version.dart';
import 'package:abakus_one_v2/features/recipes/application/use_cases/set_recipe_confidential.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_version_repository.dart';
import 'package:abakus_one_v2/features/recipes/domain/portion_definition.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_line.dart';
import 'package:abakus_one_v2/features/recipes/domain/yield.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/recipe_test_fixtures.dart';

void main() {
  group('CreateRecipe', () {
    test('creates a Recipe with an initial version 1', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
      final useCase = CreateRecipe(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialRecipeIdGenerator(),
        versionIdGenerator: SequentialRecipeVersionIdGenerator(),
        repository: recipeRepository,
        versionRepository: versionRepository,
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );

      final recipe = await useCase(
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

      expect(recipe.organizationId, 'org-1');
      final version = await versionRepository.findById(recipe.currentVersionId);
      expect(version!.versionNumber, 1);
      expect(version.lines.single.ingredientId, 'ingredient-1');
    });

    test('an unauthorized actor is denied', () async {
      final useCase = CreateRecipe(
        authorizationPolicy: const DenyAllRecipesPolicy(),
        idGenerator: SequentialRecipeIdGenerator(),
        versionIdGenerator: SequentialRecipeVersionIdGenerator(),
        repository: InMemoryRecipeRepository(),
        versionRepository: InMemoryRecipeVersionRepository(),
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );

      expect(
        () => useCase(
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
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('CreateRecipeVersion', () {
    test('adds v2 without mutating v1, and repoints currentVersionId',
        () async {
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
      final versionIdGenerator = SequentialRecipeVersionIdGenerator();
      final createRecipe = CreateRecipe(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialRecipeIdGenerator(),
        versionIdGenerator: versionIdGenerator,
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
      final v1Id = recipe.currentVersionId;

      final createVersion = CreateRecipeVersion(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        versionIdGenerator: versionIdGenerator,
        repository: recipeRepository,
        versionRepository: versionRepository,
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );
      final v2 = await createVersion(
        recipeId: recipe.id,
        lines: [
          RecipeLine(
            id: 'line-1',
            ingredientId: 'ingredient-1',
            quantity: Quantity.fromWhole(200, InventoryUnit.gram),
          ),
        ],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldInfo: Yield(
          totalQuantity: Quantity.fromWhole(200, InventoryUnit.gram),
          portionCount: 1,
        ),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(v2.versionNumber, 2);
      final updatedRecipe = await recipeRepository.findById(recipe.id);
      expect(updatedRecipe!.currentVersionId, v2.id);

      final v1 = await versionRepository.findById(v1Id);
      expect(v1!.lines.single.quantity.smallestUnits, 150,
          reason: 'v1 must remain unmutated after v2 is created');
    });

    test('an unknown recipe throws', () async {
      final useCase = CreateRecipeVersion(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        versionIdGenerator: SequentialRecipeVersionIdGenerator(),
        repository: InMemoryRecipeRepository(),
        versionRepository: InMemoryRecipeVersionRepository(),
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );

      expect(
        () => useCase(
          recipeId: 'missing',
          lines: [
            RecipeLine(
              id: 'line-1',
              ingredientId: 'ingredient-1',
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
        ),
        throwsA(isA<UnknownRecipeEntityViolation>()),
      );
    });
  });

  group('SetRecipeConfidential', () {
    test('toggles the flag and is audited', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
      final auditRepository = InMemoryRecipeAuditEntryRepository();
      final createRecipe = CreateRecipe(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialRecipeIdGenerator(),
        versionIdGenerator: SequentialRecipeVersionIdGenerator(),
        repository: recipeRepository,
        versionRepository: versionRepository,
        auditRepository: auditRepository,
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
      expect(recipe.isConfidential, isFalse);

      final useCase = SetRecipeConfidential(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        repository: recipeRepository,
        auditRepository: auditRepository,
      );
      final updated = await useCase(
        recipeId: recipe.id,
        isConfidential: true,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(updated.isConfidential, isTrue);
      final events = await auditRepository.findByTargetEntityId(recipe.id);
      expect(
        events.any((e) => e.description.contains('confidentiality')),
        isTrue,
      );
    });
  });
}
