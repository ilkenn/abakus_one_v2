import 'package:abakus_one_v2/features/allergens/data/ingredient_allergen_declaration_repository.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/menu_labels/application/identity/menu_label_rule_id_generator.dart';
import 'package:abakus_one_v2/features/menu_labels/application/identity/menu_label_suggestion_id_generator.dart';
import 'package:abakus_one_v2/features/menu_labels/application/use_cases/approve_menu_label_suggestion.dart';
import 'package:abakus_one_v2/features/menu_labels/application/use_cases/create_menu_label_rule.dart';
import 'package:abakus_one_v2/features/menu_labels/application/use_cases/evaluate_menu_label_suggestions.dart';
import 'package:abakus_one_v2/features/menu_labels/data/menu_label_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/menu_labels/data/menu_label_rule_repository.dart';
import 'package:abakus_one_v2/features/menu_labels/data/menu_label_suggestion_repository.dart';
import 'package:abakus_one_v2/features/menu_labels/domain/menu_label_type.dart';
import 'package:abakus_one_v2/features/nutrition/data/nutrition_calculation_result_repository.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_calculation_result.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_confidence.dart';
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

import '../test_support/menu_label_test_fixtures.dart';

void main() {
  group('EvaluateMenuLabelSuggestions', () {
    test(
        'creates an unapproved suggestion for a qualifying highProtein '
        'rule, and none for a non-qualifying lowCalorie rule', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
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
        ],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldAmount: Yield(
          totalQuantity: Quantity.fromWhole(200, InventoryUnit.gram),
          portionCount: 1,
        ),
        createdAt: DateTime(2026, 1, 1),
        createdByStaffId: 'manager-1',
      );
      await versionRepository.save(version);
      await recipeRepository.save(Recipe(
        id: 'recipe-1',
        organizationId: 'org-1',
        name: 'Tavuklu Bowl',
        currentVersionId: version.id,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final nutritionResultRepository =
          InMemoryNutritionCalculationResultRepository();
      await nutritionResultRepository.save(NutritionCalculationResult(
        id: 'nutrition-result-1',
        recipeId: 'recipe-1',
        recipeVersionId: 'version-1',
        totalValues:
            const NutritionValueSet(proteinMilligrams: 30000, energyKcal: 500),
        perPortionValues:
            const NutritionValueSet(proteinMilligrams: 30000, energyKcal: 500),
        portionCount: 1,
        missingIngredientIds: const [],
        status: RecipeCalculationStatus.calculated,
        confidence: NutritionConfidence.high,
        calculationRevision: 1,
        calculatedAt: DateTime(2026, 1, 2),
      ));

      final ruleRepository = InMemoryMenuLabelRuleRepository();
      final createRule = CreateMenuLabelRule(
        authorizationPolicy: const AllowAllMenuLabelsPolicy(),
        idGenerator: SequentialMenuLabelRuleIdGenerator(),
        repository: ruleRepository,
        auditRepository: InMemoryMenuLabelAuditEntryRepository(),
      );
      await createRule(
        organizationId: 'org-1',
        labelType: MenuLabelType.highProtein,
        description: 'Yüksek protein',
        thresholdMilligramsOrKcal: 25000,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );
      await createRule(
        organizationId: 'org-1',
        labelType: MenuLabelType.lowCalorie,
        description: 'Düşük kalori',
        thresholdMilligramsOrKcal: 300,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final suggestionRepository = InMemoryMenuLabelSuggestionRepository();
      final useCase = EvaluateMenuLabelSuggestions(
        authorizationPolicy: const AllowAllMenuLabelsPolicy(),
        idGenerator: SequentialMenuLabelSuggestionIdGenerator(),
        recipeRepository: recipeRepository,
        recipeVersionRepository: versionRepository,
        subRecipeRepository: InMemorySubRecipeRepository(),
        subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        nutritionResultRepository: nutritionResultRepository,
        allergenRepository: InMemoryIngredientAllergenDeclarationRepository(),
        ruleRepository: ruleRepository,
        suggestionRepository: suggestionRepository,
        auditRepository: InMemoryMenuLabelAuditEntryRepository(),
      );

      final created = await useCase(
        organizationId: 'org-1',
        recipeId: 'recipe-1',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 3),
      );

      expect(created, hasLength(1));
      expect(created.single.labelType, MenuLabelType.highProtein);
      expect(created.single.isApproved, isFalse);

      final persisted =
          await suggestionRepository.findByRecipeVersionId('version-1');
      expect(persisted, hasLength(1));
    });

    test(
        'a rule created for a different organization is never applied '
        'to this organization\'s recipe (tenant isolation)', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
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
        ],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldAmount: Yield(
          totalQuantity: Quantity.fromWhole(200, InventoryUnit.gram),
          portionCount: 1,
        ),
        createdAt: DateTime(2026, 1, 1),
        createdByStaffId: 'manager-1',
      );
      await versionRepository.save(version);
      await recipeRepository.save(Recipe(
        id: 'recipe-1',
        organizationId: 'org-1',
        name: 'Tavuklu Bowl',
        currentVersionId: version.id,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final nutritionResultRepository =
          InMemoryNutritionCalculationResultRepository();
      await nutritionResultRepository.save(NutritionCalculationResult(
        id: 'nutrition-result-1',
        recipeId: 'recipe-1',
        recipeVersionId: 'version-1',
        totalValues: const NutritionValueSet(proteinMilligrams: 30000),
        perPortionValues: const NutritionValueSet(proteinMilligrams: 30000),
        portionCount: 1,
        missingIngredientIds: const [],
        status: RecipeCalculationStatus.calculated,
        confidence: NutritionConfidence.high,
        calculationRevision: 1,
        calculatedAt: DateTime(2026, 1, 2),
      ));

      // A qualifying rule, but created for a DIFFERENT organization.
      final ruleRepository = InMemoryMenuLabelRuleRepository();
      await CreateMenuLabelRule(
        authorizationPolicy: const AllowAllMenuLabelsPolicy(),
        idGenerator: SequentialMenuLabelRuleIdGenerator(),
        repository: ruleRepository,
        auditRepository: InMemoryMenuLabelAuditEntryRepository(),
      )(
        organizationId: 'org-2',
        labelType: MenuLabelType.highProtein,
        description: 'Yüksek protein',
        thresholdMilligramsOrKcal: 25000,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final useCase = EvaluateMenuLabelSuggestions(
        authorizationPolicy: const AllowAllMenuLabelsPolicy(),
        idGenerator: SequentialMenuLabelSuggestionIdGenerator(),
        recipeRepository: recipeRepository,
        recipeVersionRepository: versionRepository,
        subRecipeRepository: InMemorySubRecipeRepository(),
        subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        nutritionResultRepository: nutritionResultRepository,
        allergenRepository: InMemoryIngredientAllergenDeclarationRepository(),
        ruleRepository: ruleRepository,
        suggestionRepository: InMemoryMenuLabelSuggestionRepository(),
        auditRepository: InMemoryMenuLabelAuditEntryRepository(),
      );

      final created = await useCase(
        organizationId: 'org-1',
        recipeId: 'recipe-1',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 3),
      );

      expect(created, isEmpty,
          reason: 'org-2\'s rule must never apply to an org-1 recipe');
    });
  });

  group('ApproveMenuLabelSuggestion', () {
    test('approving records the approver and flips isApproved', () async {
      final suggestionRepository = InMemoryMenuLabelSuggestionRepository();
      final ruleRepository = InMemoryMenuLabelRuleRepository();
      final createRule = CreateMenuLabelRule(
        authorizationPolicy: const AllowAllMenuLabelsPolicy(),
        idGenerator: SequentialMenuLabelRuleIdGenerator(),
        repository: ruleRepository,
        auditRepository: InMemoryMenuLabelAuditEntryRepository(),
      );
      await createRule(
        organizationId: 'org-1',
        labelType: MenuLabelType.highFiber,
        description: 'Yüksek lif',
        thresholdMilligramsOrKcal: 5000,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
      final version = RecipeVersion(
        id: 'version-1',
        recipeId: 'recipe-1',
        versionNumber: 1,
        lines: [
          RecipeLine(
            id: 'line-1',
            ingredientId: 'beans',
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
      await versionRepository.save(version);
      await recipeRepository.save(Recipe(
        id: 'recipe-1',
        organizationId: 'org-1',
        name: 'Fasulyeli Bowl',
        currentVersionId: version.id,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final nutritionResultRepository =
          InMemoryNutritionCalculationResultRepository();
      await nutritionResultRepository.save(NutritionCalculationResult(
        id: 'nutrition-result-1',
        recipeId: 'recipe-1',
        recipeVersionId: 'version-1',
        totalValues: const NutritionValueSet(fiberMilligrams: 8000),
        perPortionValues: const NutritionValueSet(fiberMilligrams: 8000),
        portionCount: 1,
        missingIngredientIds: const [],
        status: RecipeCalculationStatus.calculated,
        confidence: NutritionConfidence.high,
        calculationRevision: 1,
        calculatedAt: DateTime(2026, 1, 2),
      ));

      final evaluate = EvaluateMenuLabelSuggestions(
        authorizationPolicy: const AllowAllMenuLabelsPolicy(),
        idGenerator: SequentialMenuLabelSuggestionIdGenerator(),
        recipeRepository: recipeRepository,
        recipeVersionRepository: versionRepository,
        subRecipeRepository: InMemorySubRecipeRepository(),
        subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        nutritionResultRepository: nutritionResultRepository,
        allergenRepository: InMemoryIngredientAllergenDeclarationRepository(),
        ruleRepository: ruleRepository,
        suggestionRepository: suggestionRepository,
        auditRepository: InMemoryMenuLabelAuditEntryRepository(),
      );
      final created = await evaluate(
        organizationId: 'org-1',
        recipeId: 'recipe-1',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 3),
      );
      expect(created, hasLength(1));

      final approve = ApproveMenuLabelSuggestion(
        authorizationPolicy: const AllowAllMenuLabelsPolicy(),
        repository: suggestionRepository,
        auditRepository: InMemoryMenuLabelAuditEntryRepository(),
      );
      final approved = await approve(
        organizationId: 'org-1',
        suggestionId: created.single.id,
        performedByStaffId: 'manager-2',
        performedAt: DateTime(2026, 1, 4),
      );

      expect(approved.isApproved, isTrue);
      expect(approved.approvedByStaffId, 'manager-2');
    });
  });
}
