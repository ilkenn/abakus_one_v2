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
import '../../domain/sub_recipe_version.dart';
import '../../domain/yield.dart';
import '../identity/sub_recipe_version_id_generator.dart';

/// Adds a new, immutable [SubRecipeVersion] to an existing [SubRecipe]
/// — manager+ (`PosAuthorizedAction.manageRecipes`), Phase 7
/// (`docs/decisions.md` ADR-024). Same never-mutate-a-prior-version
/// contract as `CreateRecipeVersion`.
class CreateSubRecipeVersion {
  const CreateSubRecipeVersion({
    required PosAuthorizationPolicy authorizationPolicy,
    required SubRecipeVersionIdGenerator versionIdGenerator,
    required SubRecipeRepository repository,
    required SubRecipeVersionRepository versionRepository,
    required RecipeAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _versionIdGenerator = versionIdGenerator,
        _repository = repository,
        _versionRepository = versionRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final SubRecipeVersionIdGenerator _versionIdGenerator;
  final SubRecipeRepository _repository;
  final SubRecipeVersionRepository _versionRepository;
  final RecipeAuditEntryRepository _auditRepository;

  Future<SubRecipeVersion> call({
    required String subRecipeId,
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

    final subRecipe = await _repository.findById(subRecipeId);
    if (subRecipe == null) {
      throw UnknownRecipeEntityViolation(
        entityName: 'SubRecipe',
        id: subRecipeId,
      );
    }

    final existingVersions =
        await _versionRepository.findBySubRecipeId(subRecipeId);
    final nextVersionNumber = existingVersions.isEmpty
        ? 1
        : existingVersions
                .map((v) => v.versionNumber)
                .reduce((a, b) => a > b ? a : b) +
            1;

    final version = SubRecipeVersion(
      id: _versionIdGenerator.nextSubRecipeVersionId(),
      subRecipeId: subRecipeId,
      versionNumber: nextVersionNumber,
      lines: List.unmodifiable(lines),
      yieldAmount: yieldInfo,
      preparationLoss: preparationLoss,
      cookingLoss: cookingLoss,
      createdAt: performedAt,
      createdByStaffId: performedByStaffId,
    );
    await _versionRepository.save(version);

    await _repository.save(subRecipe.copyWith(
      currentVersionId: version.id,
      revision: subRecipe.revision + 1,
    ));

    await _auditRepository.appendEvent(RecipeAuditEntry(
      id: '${version.id}-audit-created',
      organizationId: subRecipe.organizationId,
      actorId: performedByStaffId,
      type: RecipeAuditEventType.subRecipeVersionCreated,
      description:
          'Sub-recipe "${subRecipe.name}" new version v$nextVersionNumber created',
      targetEntityId: subRecipeId,
      timestamp: performedAt,
    ));

    return version;
  }
}
