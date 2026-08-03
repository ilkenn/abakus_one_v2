import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/recipe_audit_entry_repository.dart';
import '../../data/recipe_repository.dart';
import '../../data/recipe_version_repository.dart';
import '../../domain/cooking_loss.dart';
import '../../domain/portion_definition.dart';
import '../../domain/preparation_loss.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_audit_entry.dart';
import '../../domain/recipe_audit_event_type.dart';
import '../../domain/recipe_line.dart';
import '../../domain/recipe_version.dart';
import '../../domain/yield.dart';
import '../identity/recipe_id_generator.dart';
import '../identity/recipe_version_id_generator.dart';

/// Creates a [Recipe] together with its initial (version 1)
/// [RecipeVersion] — manager+ (`PosAuthorizedAction.manageRecipes`),
/// Phase 7 (`docs/decisions.md` ADR-024).
class CreateRecipe {
  const CreateRecipe({
    required PosAuthorizationPolicy authorizationPolicy,
    required RecipeIdGenerator idGenerator,
    required RecipeVersionIdGenerator versionIdGenerator,
    required RecipeRepository repository,
    required RecipeVersionRepository versionRepository,
    required RecipeAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _versionIdGenerator = versionIdGenerator,
        _repository = repository,
        _versionRepository = versionRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final RecipeIdGenerator _idGenerator;
  final RecipeVersionIdGenerator _versionIdGenerator;
  final RecipeRepository _repository;
  final RecipeVersionRepository _versionRepository;
  final RecipeAuditEntryRepository _auditRepository;

  Future<Recipe> call({
    required String organizationId,
    required String name,
    String? category,
    bool isConfidential = false,
    required List<RecipeLine> lines,
    required PortionDefinition portionDefinition,
    required Yield yieldInfo,
    PreparationLoss? preparationLoss,
    CookingLoss? cookingLoss,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageRecipes;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final recipeId = _idGenerator.nextRecipeId();
    final version = RecipeVersion(
      id: _versionIdGenerator.nextRecipeVersionId(),
      recipeId: recipeId,
      versionNumber: 1,
      lines: List.unmodifiable(lines),
      portionDefinition: portionDefinition,
      yieldAmount: yieldInfo,
      preparationLoss: preparationLoss,
      cookingLoss: cookingLoss,
      createdAt: performedAt,
      createdByStaffId: performedByStaffId,
    );
    await _versionRepository.save(version);

    final recipe = Recipe(
      id: recipeId,
      organizationId: organizationId,
      name: name,
      category: category,
      isConfidential: isConfidential,
      currentVersionId: version.id,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(recipe);

    await _auditRepository.appendEvent(RecipeAuditEntry(
      id: '$recipeId-audit-created',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: RecipeAuditEventType.recipeCreated,
      description: 'Recipe "$name" created (v1)',
      targetEntityId: recipeId,
      timestamp: performedAt,
    ));

    return recipe;
  }
}
