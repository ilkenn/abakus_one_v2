import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/recipe_audit_entry_repository.dart';
import '../../data/sub_recipe_repository.dart';
import '../../data/sub_recipe_version_repository.dart';
import '../../domain/cooking_loss.dart';
import '../../domain/preparation_loss.dart';
import '../../domain/recipe_audit_entry.dart';
import '../../domain/recipe_audit_event_type.dart';
import '../../domain/recipe_line.dart';
import '../../domain/sub_recipe.dart';
import '../../domain/sub_recipe_version.dart';
import '../../domain/yield.dart';
import '../identity/sub_recipe_id_generator.dart';
import '../identity/sub_recipe_version_id_generator.dart';

/// Creates a [SubRecipe] together with its initial (version 1)
/// [SubRecipeVersion] — manager+ (`PosAuthorizedAction.manageRecipes`),
/// Phase 7 (`docs/decisions.md` ADR-024).
class CreateSubRecipe {
  const CreateSubRecipe({
    required PosAuthorizationPolicy authorizationPolicy,
    required SubRecipeIdGenerator idGenerator,
    required SubRecipeVersionIdGenerator versionIdGenerator,
    required SubRecipeRepository repository,
    required SubRecipeVersionRepository versionRepository,
    required RecipeAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _versionIdGenerator = versionIdGenerator,
        _repository = repository,
        _versionRepository = versionRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final SubRecipeIdGenerator _idGenerator;
  final SubRecipeVersionIdGenerator _versionIdGenerator;
  final SubRecipeRepository _repository;
  final SubRecipeVersionRepository _versionRepository;
  final RecipeAuditEntryRepository _auditRepository;

  Future<SubRecipe> call({
    required String organizationId,
    required String name,
    bool isConfidential = false,
    required List<RecipeLine> lines,
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

    final subRecipeId = _idGenerator.nextSubRecipeId();
    final version = SubRecipeVersion(
      id: _versionIdGenerator.nextSubRecipeVersionId(),
      subRecipeId: subRecipeId,
      versionNumber: 1,
      lines: List.unmodifiable(lines),
      yieldAmount: yieldInfo,
      preparationLoss: preparationLoss,
      cookingLoss: cookingLoss,
      createdAt: performedAt,
      createdByStaffId: performedByStaffId,
    );
    await _versionRepository.save(version);

    final subRecipe = SubRecipe(
      id: subRecipeId,
      organizationId: organizationId,
      name: name,
      isConfidential: isConfidential,
      currentVersionId: version.id,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(subRecipe);

    await _auditRepository.appendEvent(RecipeAuditEntry(
      id: '$subRecipeId-audit-created',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: RecipeAuditEventType.subRecipeCreated,
      description: 'Sub-recipe "$name" created (v1)',
      targetEntityId: subRecipeId,
      timestamp: performedAt,
    ));

    return subRecipe;
  }
}
