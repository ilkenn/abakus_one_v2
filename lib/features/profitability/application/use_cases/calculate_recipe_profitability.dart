import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/money.dart';
import '../../../costing/data/cost_calculation_result_repository.dart';
import '../../../costing/domain/cost_calculation_result.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../recipes/data/recipe_repository.dart';
import '../../../recipes/domain/recipe_calculation_status.dart';
import '../../data/profitability_audit_entry_repository.dart';
import '../../data/profitability_calculation_result_repository.dart';
import '../../data/profitability_threshold_config_repository.dart';
import '../../domain/profitability_audit_entry.dart';
import '../../domain/profitability_audit_event_type.dart';
import '../../domain/profitability_calculation_result.dart';
import '../../domain/profitability_threshold_config.dart';
import '../../domain/profitability_warning_type.dart';
import '../identity/profitability_calculation_result_id_generator.dart';

/// Computes and persists a [ProfitabilityCalculationResult] for a
/// recipe's current cost data against a caller-supplied selling price
/// — admin-only (`PosAuthorizedAction.viewProfitability`), Phase 7
/// (`docs/decisions.md` ADR-024). See
/// [ProfitabilityCalculationResult]'s own doc comment for why nothing
/// here is ever called "net profit."
///
/// [netRevenue] is the selling price to evaluate against — this
/// feature has no opinion on where that price comes from (menu
/// pricing, a discount snapshot, ...); the caller resolves it.
/// [packagingCost]/[channelCost] are optional pre-resolved
/// contributions (from `features/costing`'s reference data) — `null`
/// means "not applicable to this product," not "unknown," so it never
/// blocks [RecipeCalculationStatus.calculated] on its own. Only a
/// missing [netRevenue] or an incomplete ingredient cost does.
class CalculateRecipeProfitability {
  const CalculateRecipeProfitability({
    required PosAuthorizationPolicy authorizationPolicy,
    required ProfitabilityCalculationResultIdGenerator idGenerator,
    required RecipeRepository recipeRepository,
    required CostCalculationResultRepository costResultRepository,
    required ProfitabilityCalculationResultRepository resultRepository,
    required ProfitabilityThresholdConfigRepository thresholdConfigRepository,
    required ProfitabilityAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _recipeRepository = recipeRepository,
        _costResultRepository = costResultRepository,
        _resultRepository = resultRepository,
        _thresholdConfigRepository = thresholdConfigRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final ProfitabilityCalculationResultIdGenerator _idGenerator;
  final RecipeRepository _recipeRepository;
  final CostCalculationResultRepository _costResultRepository;
  final ProfitabilityCalculationResultRepository _resultRepository;
  final ProfitabilityThresholdConfigRepository _thresholdConfigRepository;
  final ProfitabilityAuditEntryRepository _auditRepository;

  Future<ProfitabilityCalculationResult> call({
    required String branchId,
    required String recipeId,
    Money? netRevenue,
    Money? packagingCost,
    Money? channelCost,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.viewProfitability;
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

    final costResults = await _costResultRepository
        .findByRecipeVersionId(recipe.currentVersionId);
    CostCalculationResult? latestCostResult;
    for (final result in costResults) {
      if (latestCostResult == null ||
          result.calculationRevision > latestCostResult.calculationRevision) {
        latestCostResult = result;
      }
    }
    final ingredientCost =
        latestCostResult?.status == RecipeCalculationStatus.calculated
            ? latestCostResult!.totalCost
            : null;

    Money? grossContribution;
    int? marginBasisPoints;
    if (netRevenue != null && ingredientCost != null) {
      var contribution = netRevenue - ingredientCost;
      if (packagingCost != null) contribution = contribution - packagingCost;
      if (channelCost != null) contribution = contribution - channelCost;
      grossContribution = contribution;
      if (netRevenue.minorUnits != 0) {
        marginBasisPoints =
            (contribution.minorUnits * 10000) ~/ netRevenue.minorUnits;
      }
    }

    final status = (netRevenue != null && ingredientCost != null)
        ? RecipeCalculationStatus.calculated
        : RecipeCalculationStatus.incomplete;

    final thresholds =
        await _thresholdConfigRepository.findByBranchId(branchId);
    final priorResults = await _resultRepository.findByRecipeId(recipeId);
    final warnings = _evaluateWarnings(
      netRevenue: netRevenue,
      marginBasisPoints: marginBasisPoints,
      ingredientCost: ingredientCost,
      thresholds: thresholds,
      priorResults: priorResults,
    );

    final result = ProfitabilityCalculationResult(
      id: _idGenerator.nextProfitabilityCalculationResultId(),
      recipeId: recipeId,
      recipeVersionId: recipe.currentVersionId,
      netRevenue: netRevenue,
      ingredientCost: ingredientCost,
      packagingCost: packagingCost,
      channelCost: channelCost,
      grossContribution: grossContribution,
      contributionMarginBasisPoints: marginBasisPoints,
      status: status,
      warnings: warnings,
      calculationRevision: priorResults.length + 1,
      calculatedAt: performedAt,
    );
    await _resultRepository.save(result);

    await _auditRepository.appendEvent(ProfitabilityAuditEntry(
      id: '${result.id}-audit-calculated',
      organizationId: recipe.organizationId,
      actorId: performedByStaffId,
      type: ProfitabilityAuditEventType.recipeProfitabilityCalculated,
      description: 'Profitability calculated for recipe "${recipe.name}" '
          '(${warnings.length} warning(s))',
      targetEntityId: recipeId,
      timestamp: performedAt,
    ));

    return result;
  }

  List<ProfitabilityWarningType> _evaluateWarnings({
    required Money? netRevenue,
    required int? marginBasisPoints,
    required Money? ingredientCost,
    required ProfitabilityThresholdConfig? thresholds,
    required List<ProfitabilityCalculationResult> priorResults,
  }) {
    final warnings = <ProfitabilityWarningType>[];

    if (netRevenue == null) {
      warnings.add(ProfitabilityWarningType.missingPrice);
    }

    if (thresholds != null) {
      final lowMarginThreshold = thresholds.lowMarginBasisPointsThreshold;
      if (lowMarginThreshold != null &&
          marginBasisPoints != null &&
          marginBasisPoints < lowMarginThreshold) {
        warnings.add(ProfitabilityWarningType.lowMargin);
      }

      final floorPrice = thresholds.floorPriceMinorUnits;
      if (floorPrice != null &&
          netRevenue != null &&
          netRevenue.minorUnits <= floorPrice) {
        warnings.add(ProfitabilityWarningType.belowFloorSelling);
      }

      final costSpikeThreshold = thresholds.costSpikeBasisPointsThreshold;
      if (costSpikeThreshold != null &&
          ingredientCost != null &&
          priorResults.isNotEmpty) {
        final previousCost = priorResults.last.ingredientCost;
        if (previousCost != null && previousCost.minorUnits > 0) {
          final increaseBasisPoints =
              ((ingredientCost.minorUnits - previousCost.minorUnits) * 10000) ~/
                  previousCost.minorUnits;
          if (increaseBasisPoints >= costSpikeThreshold) {
            warnings.add(ProfitabilityWarningType.costSpike);
          }
        }
      }
    }

    return warnings;
  }
}
