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
import '../identity/recipe_version_id_generator.dart';

/// Adds a new, immutable [RecipeVersion] to an existing [Recipe] —
/// manager+ (`PosAuthorizedAction.manageRecipes`), Phase 7
/// (`docs/decisions.md` ADR-024). Never mutates any prior version;
/// only repoints `Recipe.currentVersionId` at the newly created one —
/// "editing a recipe never rewrites historical costs/nutrition."
class CreateRecipeVersion {
  const CreateRecipeVersion({
    required PosAuthorizationPolicy authorizationPolicy,
    required RecipeVersionIdGenerator versionIdGenerator,
    required RecipeRepository repository,
    required RecipeVersionRepository versionRepository,
    required RecipeAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _versionIdGenerator = versionIdGenerator,
        _repository = repository,
        _versionRepository = versionRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final RecipeVersionIdGenerator _versionIdGenerator;
  final RecipeRepository _repository;
  final RecipeVersionRepository _versionRepository;
  final RecipeAuditEntryRepository _auditRepository;

  Future<RecipeVersion> call({
    required String recipeId,
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

    final recipe = await _repository.findById(recipeId);
    if (recipe == null) {
      throw UnknownRecipeEntityViolation(entityName: 'Recipe', id: recipeId);
    }

    final existingVersions = await _versionRepository.findByRecipeId(recipeId);
    final nextVersionNumber = existingVersions.isEmpty
        ? 1
        : existingVersions
                .map((v) => v.versionNumber)
                .reduce((a, b) => a > b ? a : b) +
            1;

    final version = RecipeVersion(
      id: _versionIdGenerator.nextRecipeVersionId(),
      recipeId: recipeId,
      versionNumber: nextVersionNumber,
      lines: List.unmodifiable(lines),
      portionDefinition: portionDefinition,
      yieldAmount: yieldInfo,
      preparationLoss: preparationLoss,
      cookingLoss: cookingLoss,
      createdAt: performedAt,
      createdByStaffId: performedByStaffId,
    );
    await _versionRepository.save(version);

    await _repository.save(recipe.copyWith(
      currentVersionId: version.id,
      revision: recipe.revision + 1,
    ));

    await _auditRepository.appendEvent(RecipeAuditEntry(
      id: '${version.id}-audit-created',
      organizationId: recipe.organizationId,
      actorId: performedByStaffId,
      type: RecipeAuditEventType.recipeVersionCreated,
      description:
          'Recipe "${recipe.name}" new version v$nextVersionNumber created',
      targetEntityId: recipeId,
      timestamp: performedAt,
    ));

    return version;
  }
}
