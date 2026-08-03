import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../recipes/data/recipe_repository.dart';
import '../../../recipes/data/recipe_version_repository.dart';
import '../../../recipes/data/sub_recipe_repository.dart';
import '../../../recipes/data/sub_recipe_version_repository.dart';
import '../../../recipes/domain/recipe_calculation_status.dart';
import '../../../recipes/domain/recipe_line_flattener.dart';
import '../../data/nutrition_calculation_result_repository.dart';
import '../../data/nutrition_reference_entry_repository.dart';
import '../../domain/nutrition_aggregator.dart';
import '../../domain/nutrition_calculation_result.dart';
import '../../domain/nutrition_reference_entry.dart';
import '../../domain/nutrition_value_set.dart';
import '../identity/nutrition_calculation_result_id_generator.dart';

/// Computes and persists a [NutritionCalculationResult] for a
/// [Recipe]'s current (or an explicit) version — manager+
/// (`PosAuthorizedAction.manageNutrition`), Phase 7
/// (`docs/decisions.md` ADR-024). Flattens the version's lines via
/// `RecipeLineFlattener` (same nested sub-recipe expansion
/// `ResolveRecipeIngredientSnapshot`/the Bowl Builder resolver use),
/// then delegates the actual per-ingredient math to
/// [NutritionAggregator] — the same pure aggregator a future Bowl
/// Builder nutrition update can reuse directly on
/// `DynamicBowlRecipeResolution.resolvedLines` without depending on
/// `features/recipes` at all.
///
/// Cooking/preparation loss is **not** re-applied here — a
/// [RecipeVersion.yieldAmount] is defined as the recipe's actual
/// post-loss output, so loss is already baked into the yield the
/// portion-scaling below divides by; applying it a second time here
/// would double-count it.
///
/// [calculationRevision] increments per `recipeVersionId` — repeated
/// recalculation (e.g. after a `NutritionReferenceEntry` correction)
/// produces a new, separately auditable result rather than silently
/// overwriting the previous one.
class CalculateRecipeNutrition {
  CalculateRecipeNutrition({
    required PosAuthorizationPolicy authorizationPolicy,
    required NutritionCalculationResultIdGenerator idGenerator,
    required RecipeRepository recipeRepository,
    required RecipeVersionRepository recipeVersionRepository,
    required SubRecipeRepository subRecipeRepository,
    required SubRecipeVersionRepository subRecipeVersionRepository,
    required NutritionReferenceEntryRepository referenceEntryRepository,
    required NutritionCalculationResultRepository resultRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _recipeRepository = recipeRepository,
        _recipeVersionRepository = recipeVersionRepository,
        _flattener = RecipeLineFlattener(
          subRecipeRepository: subRecipeRepository,
          subRecipeVersionRepository: subRecipeVersionRepository,
        ),
        _referenceEntryRepository = referenceEntryRepository,
        _resultRepository = resultRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final NutritionCalculationResultIdGenerator _idGenerator;
  final RecipeRepository _recipeRepository;
  final RecipeVersionRepository _recipeVersionRepository;
  final RecipeLineFlattener _flattener;
  final NutritionReferenceEntryRepository _referenceEntryRepository;
  final NutritionCalculationResultRepository _resultRepository;
  static const _aggregator = NutritionAggregator();

  Future<NutritionCalculationResult> call({
    required String recipeId,
    String? recipeVersionId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageNutrition;
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
    final versionId = recipeVersionId ?? recipe.currentVersionId;
    final version = await _recipeVersionRepository.findById(versionId);
    if (version == null) {
      throw UnknownRecipeEntityViolation(
        entityName: 'RecipeVersion',
        id: versionId,
      );
    }

    final flattened = await _flattener.flatten(version.lines);

    final referencesByIngredientId = <String, NutritionReferenceEntry>{};
    for (final line in flattened) {
      if (referencesByIngredientId.containsKey(line.ingredientId)) continue;
      final entry =
          await _referenceEntryRepository.findByIngredientId(line.ingredientId);
      if (entry != null) {
        referencesByIngredientId[line.ingredientId] = entry;
      }
    }

    final outcome = _aggregator.aggregate(
      lines: flattened,
      referenceEntriesByIngredientId: referencesByIngredientId,
    );

    final portionCount = version.yieldAmount.portionCount;
    final perPortion = NutritionValueSet(
      energyKcal: _divide(outcome.totalValues.energyKcal, portionCount),
      proteinMilligrams:
          _divide(outcome.totalValues.proteinMilligrams, portionCount),
      carbohydrateMilligrams:
          _divide(outcome.totalValues.carbohydrateMilligrams, portionCount),
      fatMilligrams: _divide(outcome.totalValues.fatMilligrams, portionCount),
      saturatedFatMilligrams:
          _divide(outcome.totalValues.saturatedFatMilligrams, portionCount),
      fiberMilligrams:
          _divide(outcome.totalValues.fiberMilligrams, portionCount),
      sugarMilligrams:
          _divide(outcome.totalValues.sugarMilligrams, portionCount),
      saltMilligrams: _divide(outcome.totalValues.saltMilligrams, portionCount),
      sodiumMilligrams:
          _divide(outcome.totalValues.sodiumMilligrams, portionCount),
    );

    final priorResults =
        await _resultRepository.findByRecipeVersionId(version.id);

    final result = NutritionCalculationResult(
      id: _idGenerator.nextNutritionCalculationResultId(),
      recipeId: recipeId,
      recipeVersionId: version.id,
      totalValues: outcome.totalValues,
      perPortionValues: perPortion,
      portionCount: portionCount,
      missingIngredientIds: outcome.missingIngredientIds,
      status: outcome.missingIngredientIds.isEmpty
          ? RecipeCalculationStatus.calculated
          : RecipeCalculationStatus.incomplete,
      confidence: outcome.confidence,
      calculationRevision: priorResults.length + 1,
      calculatedAt: performedAt,
    );
    await _resultRepository.save(result);
    return result;
  }

  int? _divide(int? value, int portionCount) {
    if (value == null) return null;
    return value ~/ portionCount;
  }
}
