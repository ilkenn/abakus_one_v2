import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/bowl_builder/application/identity/bowl_builder_ingredient_recipe_mapping_id_generator.dart';
import 'package:abakus_one_v2/features/bowl_builder/application/use_cases/set_bowl_builder_ingredient_mapping.dart';
import 'package:abakus_one_v2/features/bowl_builder/data/bowl_builder_ingredient_recipe_mapping_repository.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_audit_entry_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../recipes/test_support/recipe_test_fixtures.dart';

void main() {
  group('SetBowlBuilderIngredientMapping', () {
    test('creates a new mapping at revision 1', () async {
      final repository = InMemoryBowlBuilderIngredientRecipeMappingRepository();
      final useCase = SetBowlBuilderIngredientMapping(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialBowlBuilderIngredientRecipeMappingIdGenerator(),
        repository: repository,
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );

      final mapping = await useCase(
        organizationId: 'org-1',
        bowlBuilderIngredientId: 'chicken',
        inventoryIngredientId: 'ingredient-chicken',
        quantityPerSelection: Quantity.fromWhole(50, InventoryUnit.gram),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(mapping.revision, 1);
      final found = await repository.findByBowlBuilderIngredientId('chicken');
      expect(found!.inventoryIngredientId, 'ingredient-chicken');
    });

    test('a second call for the same ingredient upserts (same id, revision 2)',
        () async {
      final repository = InMemoryBowlBuilderIngredientRecipeMappingRepository();
      final useCase = SetBowlBuilderIngredientMapping(
        authorizationPolicy: const AllowAllRecipesPolicy(),
        idGenerator: SequentialBowlBuilderIngredientRecipeMappingIdGenerator(),
        repository: repository,
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );

      final first = await useCase(
        organizationId: 'org-1',
        bowlBuilderIngredientId: 'chicken',
        inventoryIngredientId: 'ingredient-chicken',
        quantityPerSelection: Quantity.fromWhole(50, InventoryUnit.gram),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );
      final second = await useCase(
        organizationId: 'org-1',
        bowlBuilderIngredientId: 'chicken',
        inventoryIngredientId: 'ingredient-chicken',
        quantityPerSelection: Quantity.fromWhole(60, InventoryUnit.gram),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(second.id, first.id);
      expect(second.revision, 2);
      expect(second.quantityPerSelection.smallestUnits, 60);
      final all = await repository.findByOrganizationId('org-1');
      expect(all, hasLength(1), reason: 'must upsert, not create a duplicate');
    });

    test('an unauthorized actor is denied', () async {
      final useCase = SetBowlBuilderIngredientMapping(
        authorizationPolicy: const DenyAllRecipesPolicy(),
        idGenerator: SequentialBowlBuilderIngredientRecipeMappingIdGenerator(),
        repository: InMemoryBowlBuilderIngredientRecipeMappingRepository(),
        auditRepository: InMemoryRecipeAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          bowlBuilderIngredientId: 'chicken',
          inventoryIngredientId: 'ingredient-chicken',
          quantityPerSelection: Quantity.fromWhole(50, InventoryUnit.gram),
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
