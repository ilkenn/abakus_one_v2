import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/costing/data/cost_calculation_result_repository.dart';
import 'package:abakus_one_v2/features/costing/domain/cost_calculation_result.dart';
import 'package:abakus_one_v2/features/costing/domain/costing_method.dart';
import 'package:abakus_one_v2/features/profitability/application/identity/profitability_calculation_result_id_generator.dart';
import 'package:abakus_one_v2/features/profitability/application/identity/profitability_threshold_config_id_generator.dart';
import 'package:abakus_one_v2/features/profitability/application/use_cases/calculate_recipe_profitability.dart';
import 'package:abakus_one_v2/features/profitability/application/use_cases/set_profitability_threshold_config.dart';
import 'package:abakus_one_v2/features/profitability/data/profitability_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/profitability/data/profitability_calculation_result_repository.dart';
import 'package:abakus_one_v2/features/profitability/data/profitability_threshold_config_repository.dart';
import 'package:abakus_one_v2/features/profitability/domain/profitability_warning_type.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_repository.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_calculation_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/profitability_test_fixtures.dart';

void main() {
  Future<Recipe> seedRecipe(RecipeRepository repository) async {
    final recipe = Recipe(
      id: 'recipe-1',
      organizationId: 'org-1',
      name: 'Tavuklu Bowl',
      currentVersionId: 'version-1',
      createdAt: DateTime(2026, 1, 1),
      revision: 1,
    );
    await repository.save(recipe);
    return recipe;
  }

  Future<void> seedCostResult(
    CostCalculationResultRepository repository,
    Money totalCost, {
    int calculationRevision = 1,
  }) async {
    await repository.save(CostCalculationResult(
      id: 'cost-result-$calculationRevision',
      recipeId: 'recipe-1',
      recipeVersionId: 'version-1',
      totalCost: totalCost,
      perPortionCost: totalCost,
      portionCount: 1,
      missingIngredientIds: const [],
      status: RecipeCalculationStatus.calculated,
      costingMethod: CostingMethod.latestPurchase,
      calculationRevision: calculationRevision,
      calculatedAt: DateTime(2026, 1, 1),
    ));
  }

  group('CalculateRecipeProfitability', () {
    test(
        'computes gross contribution and margin with no warnings when no '
        'thresholds are configured', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final costResultRepository = InMemoryCostCalculationResultRepository();
      await seedRecipe(recipeRepository);
      await seedCostResult(
          costResultRepository, Money.fromWhole(10, Currency.tryLira));

      final useCase = CalculateRecipeProfitability(
        authorizationPolicy: const AllowAllProfitabilityPolicy(),
        idGenerator: SequentialProfitabilityCalculationResultIdGenerator(),
        recipeRepository: recipeRepository,
        costResultRepository: costResultRepository,
        resultRepository: InMemoryProfitabilityCalculationResultRepository(),
        thresholdConfigRepository:
            InMemoryProfitabilityThresholdConfigRepository(),
        auditRepository: InMemoryProfitabilityAuditEntryRepository(),
      );

      final result = await useCase(
        branchId: 'branch-1',
        recipeId: 'recipe-1',
        netRevenue: Money.fromWhole(20, Currency.tryLira),
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(result.grossContribution!.minorUnits, 1000);
      expect(result.contributionMarginBasisPoints, 5000);
      expect(result.status, RecipeCalculationStatus.calculated);
      expect(result.warnings, isEmpty);
    });

    test(
        'a missing selling price produces missingPrice warning and '
        'incomplete status', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final costResultRepository = InMemoryCostCalculationResultRepository();
      await seedRecipe(recipeRepository);
      await seedCostResult(
          costResultRepository, Money.fromWhole(10, Currency.tryLira));

      final useCase = CalculateRecipeProfitability(
        authorizationPolicy: const AllowAllProfitabilityPolicy(),
        idGenerator: SequentialProfitabilityCalculationResultIdGenerator(),
        recipeRepository: recipeRepository,
        costResultRepository: costResultRepository,
        resultRepository: InMemoryProfitabilityCalculationResultRepository(),
        thresholdConfigRepository:
            InMemoryProfitabilityThresholdConfigRepository(),
        auditRepository: InMemoryProfitabilityAuditEntryRepository(),
      );

      final result = await useCase(
        branchId: 'branch-1',
        recipeId: 'recipe-1',
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(result.status, RecipeCalculationStatus.incomplete);
      expect(result.warnings, contains(ProfitabilityWarningType.missingPrice));
      expect(result.grossContribution, isNull);
    });

    test('a margin below the configured floor produces lowMargin warning',
        () async {
      final recipeRepository = InMemoryRecipeRepository();
      final costResultRepository = InMemoryCostCalculationResultRepository();
      await seedRecipe(recipeRepository);
      // Cost 18, revenue 20 -> margin 10% (1000bps), below a 4000bps floor.
      await seedCostResult(
          costResultRepository, Money.fromWhole(18, Currency.tryLira));

      final thresholdRepository =
          InMemoryProfitabilityThresholdConfigRepository();
      await SetProfitabilityThresholdConfig(
        authorizationPolicy: const AllowAllProfitabilityPolicy(),
        idGenerator: SequentialProfitabilityThresholdConfigIdGenerator(),
        repository: thresholdRepository,
        auditRepository: InMemoryProfitabilityAuditEntryRepository(),
      )(
        organizationId: 'org-1',
        branchId: 'branch-1',
        lowMarginBasisPointsThreshold: 4000,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final useCase = CalculateRecipeProfitability(
        authorizationPolicy: const AllowAllProfitabilityPolicy(),
        idGenerator: SequentialProfitabilityCalculationResultIdGenerator(),
        recipeRepository: recipeRepository,
        costResultRepository: costResultRepository,
        resultRepository: InMemoryProfitabilityCalculationResultRepository(),
        thresholdConfigRepository: thresholdRepository,
        auditRepository: InMemoryProfitabilityAuditEntryRepository(),
      );

      final result = await useCase(
        branchId: 'branch-1',
        recipeId: 'recipe-1',
        netRevenue: Money.fromWhole(20, Currency.tryLira),
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(result.warnings, contains(ProfitabilityWarningType.lowMargin));
    });

    test(
        'a selling price at or below the floor produces belowFloorSelling '
        'warning', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final costResultRepository = InMemoryCostCalculationResultRepository();
      await seedRecipe(recipeRepository);
      await seedCostResult(
          costResultRepository, Money.fromWhole(5, Currency.tryLira));

      final thresholdRepository =
          InMemoryProfitabilityThresholdConfigRepository();
      await SetProfitabilityThresholdConfig(
        authorizationPolicy: const AllowAllProfitabilityPolicy(),
        idGenerator: SequentialProfitabilityThresholdConfigIdGenerator(),
        repository: thresholdRepository,
        auditRepository: InMemoryProfitabilityAuditEntryRepository(),
      )(
        organizationId: 'org-1',
        branchId: 'branch-1',
        floorPriceMinorUnits: Money.fromWhole(10, Currency.tryLira).minorUnits,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final useCase = CalculateRecipeProfitability(
        authorizationPolicy: const AllowAllProfitabilityPolicy(),
        idGenerator: SequentialProfitabilityCalculationResultIdGenerator(),
        recipeRepository: recipeRepository,
        costResultRepository: costResultRepository,
        resultRepository: InMemoryProfitabilityCalculationResultRepository(),
        thresholdConfigRepository: thresholdRepository,
        auditRepository: InMemoryProfitabilityAuditEntryRepository(),
      );

      final result = await useCase(
        branchId: 'branch-1',
        recipeId: 'recipe-1',
        netRevenue: Money.fromWhole(8, Currency.tryLira),
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(result.warnings,
          contains(ProfitabilityWarningType.belowFloorSelling));
    });

    test(
        'an ingredient cost jump beyond the configured threshold produces '
        'costSpike warning on the second calculation', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final costResultRepository = InMemoryCostCalculationResultRepository();
      await seedRecipe(recipeRepository);

      final thresholdRepository =
          InMemoryProfitabilityThresholdConfigRepository();
      await SetProfitabilityThresholdConfig(
        authorizationPolicy: const AllowAllProfitabilityPolicy(),
        idGenerator: SequentialProfitabilityThresholdConfigIdGenerator(),
        repository: thresholdRepository,
        auditRepository: InMemoryProfitabilityAuditEntryRepository(),
      )(
        organizationId: 'org-1',
        branchId: 'branch-1',
        costSpikeBasisPointsThreshold: 2000, // 20%
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final resultRepository =
          InMemoryProfitabilityCalculationResultRepository();
      final useCase = CalculateRecipeProfitability(
        authorizationPolicy: const AllowAllProfitabilityPolicy(),
        idGenerator: SequentialProfitabilityCalculationResultIdGenerator(),
        recipeRepository: recipeRepository,
        costResultRepository: costResultRepository,
        resultRepository: resultRepository,
        thresholdConfigRepository: thresholdRepository,
        auditRepository: InMemoryProfitabilityAuditEntryRepository(),
      );

      await seedCostResult(
          costResultRepository, Money.fromWhole(10, Currency.tryLira));
      final first = await useCase(
        branchId: 'branch-1',
        recipeId: 'recipe-1',
        netRevenue: Money.fromWhole(20, Currency.tryLira),
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 2),
      );
      expect(
          first.warnings, isNot(contains(ProfitabilityWarningType.costSpike)));

      // Cost jumps from 10 to 13 (+30%) -> exceeds the 20% threshold.
      await seedCostResult(
        costResultRepository,
        Money.fromWhole(13, Currency.tryLira),
        calculationRevision: 2,
      );
      final second = await useCase(
        branchId: 'branch-1',
        recipeId: 'recipe-1',
        netRevenue: Money.fromWhole(20, Currency.tryLira),
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 3),
      );

      expect(second.warnings, contains(ProfitabilityWarningType.costSpike));
    });

    test('an unauthorized actor is denied', () async {
      final recipeRepository = InMemoryRecipeRepository();
      final costResultRepository = InMemoryCostCalculationResultRepository();
      await seedRecipe(recipeRepository);

      final useCase = CalculateRecipeProfitability(
        authorizationPolicy: const DenyAllProfitabilityPolicy(),
        idGenerator: SequentialProfitabilityCalculationResultIdGenerator(),
        recipeRepository: recipeRepository,
        costResultRepository: costResultRepository,
        resultRepository: InMemoryProfitabilityCalculationResultRepository(),
        thresholdConfigRepository:
            InMemoryProfitabilityThresholdConfigRepository(),
        auditRepository: InMemoryProfitabilityAuditEntryRepository(),
      );

      expect(
        () => useCase(
          branchId: 'branch-1',
          recipeId: 'recipe-1',
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 2),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
