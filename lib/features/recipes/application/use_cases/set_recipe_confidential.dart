import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/recipe_audit_entry_repository.dart';
import '../../data/recipe_repository.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_audit_entry.dart';
import '../../domain/recipe_audit_event_type.dart';

/// Toggles a [Recipe]'s [Recipe.isConfidential] flag — manager+
/// (`PosAuthorizedAction.manageRecipes`), Phase 7
/// (`docs/decisions.md` ADR-024). Always audited — flipping
/// confidentiality is a meaningful visibility change, not a routine
/// edit.
class SetRecipeConfidential {
  const SetRecipeConfidential({
    required PosAuthorizationPolicy authorizationPolicy,
    required RecipeRepository repository,
    required RecipeAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final RecipeRepository _repository;
  final RecipeAuditEntryRepository _auditRepository;

  Future<Recipe> call({
    required String recipeId,
    required bool isConfidential,
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

    final updated = recipe.copyWith(
      isConfidential: isConfidential,
      revision: recipe.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(RecipeAuditEntry(
      id: '$recipeId-audit-confidentiality-${performedAt.microsecondsSinceEpoch}',
      organizationId: recipe.organizationId,
      actorId: performedByStaffId,
      type: RecipeAuditEventType.recipeConfidentialityChanged,
      description:
          'Recipe "${recipe.name}" confidentiality set to $isConfidential',
      targetEntityId: recipeId,
      timestamp: performedAt,
    ));

    return updated;
  }
}
