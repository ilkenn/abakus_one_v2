import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/costing/application/identity/cost_calculation_result_id_generator.dart';
import 'package:abakus_one_v2/features/costing/application/identity/purchase_price_id_generator.dart';
import 'package:abakus_one_v2/features/costing/application/use_cases/calculate_recipe_cost.dart';
import 'package:abakus_one_v2/features/costing/application/use_cases/record_purchase_price.dart';
import 'package:abakus_one_v2/features/costing/data/cost_calculation_result_repository.dart';
import 'package:abakus_one_v2/features/costing/data/costing_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/costing/data/purchase_price_repository.dart';
import 'package:abakus_one_v2/features/costing/domain/costing_method.dart';
import 'package:abakus_one_v2/features/costing/domain/latest_purchase_cost_resolver.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
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
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/costing_test_fixtures.dart';

void main() {
  group('CalculateRecipeCost', () {
    test(
        'sums known ingredient costs, flags the unmapped one as missing '
        '(incomplete status), and derives per-portion cost', () async {
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
          RecipeLine(
            id: 'line-2',
            ingredientId: 'unmapped',
            quantity: Quantity.fromWhole(50, InventoryUnit.gram),
          ),
        ],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldAmount: Yield(
          totalQuantity: Quantity.fromWhole(250, InventoryUnit.gram),
          portionCount: 2,
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

      final purchasePriceRepository = InMemoryPurchasePriceRepository();
      final recordPurchase = RecordPurchasePrice(
        authorizationPolicy: const AllowAllCostingPolicy(),
        idGenerator: SequentialPurchasePriceIdGenerator(),
        repository: purchasePriceRepository,
        auditRepository: InMemoryCostingAuditEntryRepository(),
      );
      // 100 TRY per kg of chicken -> 200g costs 20 TRY.
      await recordPurchase(
        organizationId: 'org-1',
        ingredientId: 'chicken',
        pricePerUnit: Money.fromWhole(100, Currency.tryLira),
        unit: InventoryUnit.kilogram,
        quantityPurchased: Quantity.fromWhole(5, InventoryUnit.kilogram),
        recordedAt: DateTime(2026, 1, 1),
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final useCase = CalculateRecipeCost(
        authorizationPolicy: const AllowAllCostingPolicy(),
        idGenerator: SequentialCostCalculationResultIdGenerator(),
        recipeRepository: recipeRepository,
        recipeVersionRepository: versionRepository,
        subRecipeRepository: InMemorySubRecipeRepository(),
        subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        resultRepository: InMemoryCostCalculationResultRepository(),
        auditRepository: InMemoryCostingAuditEntryRepository(),
      );

      // The recipe line is in grams, but the resolver requires an exact
      // unit match against the line's unit, so also record a gram-
      // denominated price: 0.10 TRY/gram (== 100 TRY/kg).
      await recordPurchase(
        organizationId: 'org-1',
        ingredientId: 'chicken',
        pricePerUnit: const Money(10, Currency.tryLira),
        unit: InventoryUnit.gram,
        quantityPurchased: Quantity.fromWhole(1000, InventoryUnit.gram),
        recordedAt: DateTime(2026, 1, 2),
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 2),
      );

      final result = await useCase(
        recipeId: 'recipe-1',
        costingMethod: CostingMethod.latestPurchase,
        resolver:
            LatestPurchaseCostResolver(repository: purchasePriceRepository),
        currency: Currency.tryLira,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 3),
      );

      // 0.10 TRY/gram * 200g = 20.00 TRY = 2000 minor units.
      expect(result.totalCost!.minorUnits, 2000);
      expect(result.missingIngredientIds, ['unmapped']);
      expect(result.status, RecipeCalculationStatus.incomplete);
      // 2 portions -> per-portion is half.
      expect(result.perPortionCost!.minorUnits, 1000);
      expect(result.calculationRevision, 1);
    });

    test('an unauthorized actor is denied', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final versionRepository = InMemoryRecipeVersionRepository();
      final version = RecipeVersion(
        id: 'version-1',
        recipeId: 'recipe-1',
        versionNumber: 1,
        lines: const [],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldAmount: Yield(
          totalQuantity: Quantity.fromWhole(1, InventoryUnit.gram),
          portionCount: 1,
        ),
        createdAt: DateTime(2026, 1, 1),
        createdByStaffId: 'manager-1',
      );
      await versionRepository.save(version);
      await recipeRepository.save(Recipe(
        id: 'recipe-1',
        organizationId: 'org-1',
        name: 'Empty',
        currentVersionId: version.id,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final useCase = CalculateRecipeCost(
        authorizationPolicy: const DenyAllCostingPolicy(),
        idGenerator: SequentialCostCalculationResultIdGenerator(),
        recipeRepository: recipeRepository,
        recipeVersionRepository: versionRepository,
        subRecipeRepository: InMemorySubRecipeRepository(),
        subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        resultRepository: InMemoryCostCalculationResultRepository(),
        auditRepository: InMemoryCostingAuditEntryRepository(),
      );

      expect(
        () => useCase(
          recipeId: 'recipe-1',
          costingMethod: CostingMethod.standard,
          resolver: LatestPurchaseCostResolver(
              repository: InMemoryPurchasePriceRepository()),
          currency: Currency.tryLira,
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
