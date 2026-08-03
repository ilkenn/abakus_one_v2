import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../recipes/data/recipe_repository.dart';
import '../../../recipes/data/recipe_version_repository.dart';
import '../../../recipes/data/sub_recipe_repository.dart';
import '../../../recipes/data/sub_recipe_version_repository.dart';
import '../../../recipes/domain/recipe_calculation_status.dart';
import '../../../recipes/domain/recipe_line_flattener.dart';
import '../../data/cost_calculation_result_repository.dart';
import '../../data/costing_audit_entry_repository.dart';
import '../../domain/cost_aggregator.dart';
import '../../domain/cost_calculation_result.dart';
import '../../domain/costing_audit_entry.dart';
import '../../domain/costing_audit_event_type.dart';
import '../../domain/costing_method.dart';
import '../../domain/ingredient_cost_resolver.dart';
import '../../domain/resolved_ingredient_cost.dart';
import '../identity/cost_calculation_result_id_generator.dart';

/// Computes and persists a [CostCalculationResult] for a [Recipe]'s
/// current version, using a caller-selected [CostingMethod]'s
/// resolver — admin-only
/// (`PosAuthorizedAction.manageCostingConfiguration`), Phase 7
/// (`docs/decisions.md` ADR-024). Flattens the version's lines via
/// `RecipeLineFlattener` (same shared flattening `CalculateRecipeNutrition`
/// uses), then delegates the actual summation to [CostAggregator] —
/// mirrors `CalculateRecipeNutrition`/`NutritionAggregator` exactly.
class CalculateRecipeCost {
  CalculateRecipeCost({
    required PosAuthorizationPolicy authorizationPolicy,
    required CostCalculationResultIdGenerator idGenerator,
    required RecipeRepository recipeRepository,
    required RecipeVersionRepository recipeVersionRepository,
    required SubRecipeRepository subRecipeRepository,
    required SubRecipeVersionRepository subRecipeVersionRepository,
    required CostCalculationResultRepository resultRepository,
    required CostingAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _recipeRepository = recipeRepository,
        _recipeVersionRepository = recipeVersionRepository,
        _flattener = RecipeLineFlattener(
          subRecipeRepository: subRecipeRepository,
          subRecipeVersionRepository: subRecipeVersionRepository,
        ),
        _resultRepository = resultRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final CostCalculationResultIdGenerator _idGenerator;
  final RecipeRepository _recipeRepository;
  final RecipeVersionRepository _recipeVersionRepository;
  final RecipeLineFlattener _flattener;
  final CostCalculationResultRepository _resultRepository;
  final CostingAuditEntryRepository _auditRepository;
  static const _aggregator = CostAggregator();

  Future<CostCalculationResult> call({
    required String recipeId,
    required CostingMethod costingMethod,
    required IngredientCostResolver resolver,
    required Currency currency,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageCostingConfiguration;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final recipe = await _recipeRepository.findById(recipeId);
    if (recipe == null) {
      throw UnknownRecipeEntityViolation(entityName: 'Recipe', id: recipeId);
    }
    final version =
        await _recipeVersionRepository.findById(recipe.currentVersionId);
    if (version == null) {
      throw UnknownRecipeEntityViolation(
        entityName: 'RecipeVersion',
        id: recipe.currentVersionId,
      );
    }

    final flattened = await _flattener.flatten(version.lines);

    final resolvedByIngredientId = <String, ResolvedIngredientCost>{};
    for (final line in flattened) {
      if (resolvedByIngredientId.containsKey(line.ingredientId)) continue;
      final unitCost = await resolver.resolveUnitCost(
        ingredientId: line.ingredientId,
        unit: line.quantity.unit,
      );
      if (unitCost != null) {
        resolvedByIngredientId[line.ingredientId] = ResolvedIngredientCost(
          unitCost: unitCost,
          unit: line.quantity.unit,
        );
      }
    }

    final outcome = _aggregator.aggregate(
      lines: flattened,
      resolvedCostsByIngredientId: resolvedByIngredientId,
      currency: currency,
    );

    final portionCount = version.yieldAmount.portionCount;
    final total = outcome.totalCost;
    final perPortionCost = total == null
        ? null
        : Money(total.minorUnits ~/ portionCount, total.currency);

    final priorResults =
        await _resultRepository.findByRecipeVersionId(version.id);

    final result = CostCalculationResult(
      id: _idGenerator.nextCostCalculationResultId(),
      recipeId: recipeId,
      recipeVersionId: version.id,
      totalCost: outcome.totalCost,
      perPortionCost: perPortionCost,
      portionCount: portionCount,
      missingIngredientIds: outcome.missingIngredientIds,
      status: outcome.missingIngredientIds.isEmpty
          ? RecipeCalculationStatus.calculated
          : RecipeCalculationStatus.incomplete,
      costingMethod: costingMethod,
      calculationRevision: priorResults.length + 1,
      calculatedAt: performedAt,
    );
    await _resultRepository.save(result);

    await _auditRepository.appendEvent(CostingAuditEntry(
      id: '${version.id}-audit-cost-calculated-'
          '${performedAt.microsecondsSinceEpoch}',
      organizationId: recipe.organizationId,
      actorId: performedByStaffId,
      type: CostingAuditEventType.recipeCostCalculated,
      description: 'Cost calculated for recipe "${recipe.name}" '
          'v${version.versionNumber} using ${costingMethod.name}',
      targetEntityId: recipeId,
      timestamp: performedAt,
    ));

    return result;
  }
}
