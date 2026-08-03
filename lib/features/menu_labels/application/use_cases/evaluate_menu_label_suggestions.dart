import '../../../../core/errors/business_rule_violation.dart';
import '../../../allergens/data/ingredient_allergen_declaration_repository.dart';
import '../../../allergens/domain/ingredient_allergen_declaration.dart';
import '../../../nutrition/data/nutrition_calculation_result_repository.dart';
import '../../../nutrition/domain/nutrition_calculation_result.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../recipes/data/recipe_repository.dart';
import '../../../recipes/data/recipe_version_repository.dart';
import '../../../recipes/data/sub_recipe_repository.dart';
import '../../../recipes/data/sub_recipe_version_repository.dart';
import '../../../recipes/domain/recipe_line_flattener.dart';
import '../../data/menu_label_audit_entry_repository.dart';
import '../../data/menu_label_rule_repository.dart';
import '../../data/menu_label_suggestion_repository.dart';
import '../../domain/menu_label_audit_entry.dart';
import '../../domain/menu_label_audit_event_type.dart';
import '../../domain/menu_label_rule_evaluator.dart';
import '../../domain/menu_label_suggestion.dart';
import '../identity/menu_label_suggestion_id_generator.dart';

/// Runs every active [MenuLabelRule] against one recipe's current
/// version and persists a [MenuLabelSuggestion] for each one that
/// qualifies — manager+ (`PosAuthorizedAction.manageNutrition`), Phase
/// 7 (`docs/decisions.md` ADR-024). A rule that does **not** qualify
/// produces no row at all (a suggestion row is itself the positive
/// claim "evidence found"; there is nothing honest to record about a
/// negative result beyond what already exists in the rule itself).
/// Every created suggestion starts unapproved — see
/// `MenuLabelSuggestion.isApproved`'s doc comment.
class EvaluateMenuLabelSuggestions {
  EvaluateMenuLabelSuggestions({
    required PosAuthorizationPolicy authorizationPolicy,
    required MenuLabelSuggestionIdGenerator idGenerator,
    required RecipeRepository recipeRepository,
    required RecipeVersionRepository recipeVersionRepository,
    required SubRecipeRepository subRecipeRepository,
    required SubRecipeVersionRepository subRecipeVersionRepository,
    required NutritionCalculationResultRepository nutritionResultRepository,
    required IngredientAllergenDeclarationRepository allergenRepository,
    required MenuLabelRuleRepository ruleRepository,
    required MenuLabelSuggestionRepository suggestionRepository,
    required MenuLabelAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _recipeRepository = recipeRepository,
        _recipeVersionRepository = recipeVersionRepository,
        _flattener = RecipeLineFlattener(
          subRecipeRepository: subRecipeRepository,
          subRecipeVersionRepository: subRecipeVersionRepository,
        ),
        _nutritionResultRepository = nutritionResultRepository,
        _allergenRepository = allergenRepository,
        _ruleRepository = ruleRepository,
        _suggestionRepository = suggestionRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final MenuLabelSuggestionIdGenerator _idGenerator;
  final RecipeRepository _recipeRepository;
  final RecipeVersionRepository _recipeVersionRepository;
  final RecipeLineFlattener _flattener;
  final NutritionCalculationResultRepository _nutritionResultRepository;
  final IngredientAllergenDeclarationRepository _allergenRepository;
  final MenuLabelRuleRepository _ruleRepository;
  final MenuLabelSuggestionRepository _suggestionRepository;
  final MenuLabelAuditEntryRepository _auditRepository;
  static const _evaluator = MenuLabelRuleEvaluator();

  Future<List<MenuLabelSuggestion>> call({
    required String organizationId,
    required String recipeId,
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
    final version =
        await _recipeVersionRepository.findById(recipe.currentVersionId);
    if (version == null) {
      throw UnknownRecipeEntityViolation(
        entityName: 'RecipeVersion',
        id: recipe.currentVersionId,
      );
    }

    final flattened = await _flattener.flatten(version.lines);
    final ingredientIds = flattened.map((l) => l.ingredientId).toSet().toList();

    final nutritionResults =
        await _nutritionResultRepository.findByRecipeVersionId(version.id);
    NutritionCalculationResult? latestNutritionResult;
    for (final result in nutritionResults) {
      if (latestNutritionResult == null ||
          result.calculationRevision >
              latestNutritionResult.calculationRevision) {
        latestNutritionResult = result;
      }
    }

    final declarationsByIngredientId =
        <String, List<IngredientAllergenDeclaration>>{};
    for (final ingredientId in ingredientIds) {
      declarationsByIngredientId[ingredientId] =
          await _allergenRepository.findByIngredientId(ingredientId);
    }

    final activeRules = await _ruleRepository.findAllActive();
    final created = <MenuLabelSuggestion>[];
    for (final rule in activeRules) {
      final evaluation = _evaluator.evaluate(
        rule: rule,
        nutritionResult: latestNutritionResult,
        ingredientIds: ingredientIds,
        allergenDeclarationsByIngredientId: declarationsByIngredientId,
      );
      if (!evaluation.qualifies) continue;

      final suggestion = MenuLabelSuggestion(
        id: _idGenerator.nextMenuLabelSuggestionId(),
        recipeId: recipeId,
        recipeVersionId: version.id,
        labelType: rule.labelType,
        ruleId: rule.id,
        ruleVersion: rule.ruleVersion,
        evidenceSummary: evaluation.evidenceSummary,
        isApproved: false,
        createdAt: performedAt,
      );
      await _suggestionRepository.save(suggestion);
      created.add(suggestion);
    }

    await _auditRepository.appendEvent(MenuLabelAuditEntry(
      id: '${version.id}-audit-evaluated-'
          '${performedAt.microsecondsSinceEpoch}',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: MenuLabelAuditEventType.suggestionsEvaluated,
      description: 'Menu label suggestions evaluated for recipe '
          '"${recipe.name}" v${version.versionNumber}: ${created.length} '
          'qualifying label(s) out of ${activeRules.length} active rule(s)',
      targetEntityId: recipeId,
      timestamp: performedAt,
    ));

    return created;
  }
}
