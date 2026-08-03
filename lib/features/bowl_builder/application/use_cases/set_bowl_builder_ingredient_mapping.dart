import '../../../../core/errors/business_rule_violation.dart';
import '../../../inventory/domain/quantity.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../recipes/data/recipe_audit_entry_repository.dart';
import '../../../recipes/domain/recipe_audit_entry.dart';
import '../../../recipes/domain/recipe_audit_event_type.dart';
import '../../data/bowl_builder_ingredient_recipe_mapping_repository.dart';
import '../../domain/models/bowl_builder_ingredient_recipe_mapping.dart';
import '../identity/bowl_builder_ingredient_recipe_mapping_id_generator.dart';

/// Configures (or reconfigures) the recipe/stock effect of one Bowl
/// Builder ingredient — manager+ (`PosAuthorizedAction.manageRecipes`,
/// reused rather than adding a Bowl-Builder-specific action for the
/// same "configures recipe composition" act), Phase 7
/// (`docs/decisions.md` ADR-024). Upserts by `bowlBuilderIngredientId`
/// — one mapping per Bowl Builder ingredient, never a growing history
/// of superseded ones.
class SetBowlBuilderIngredientMapping {
  const SetBowlBuilderIngredientMapping({
    required PosAuthorizationPolicy authorizationPolicy,
    required BowlBuilderIngredientRecipeMappingIdGenerator idGenerator,
    required BowlBuilderIngredientRecipeMappingRepository repository,
    required RecipeAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final BowlBuilderIngredientRecipeMappingIdGenerator _idGenerator;
  final BowlBuilderIngredientRecipeMappingRepository _repository;
  final RecipeAuditEntryRepository _auditRepository;

  Future<BowlBuilderIngredientRecipeMapping> call({
    required String organizationId,
    required String bowlBuilderIngredientId,
    required String inventoryIngredientId,
    required Quantity quantityPerSelection,
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

    final existing = await _repository
        .findByBowlBuilderIngredientId(bowlBuilderIngredientId);
    final mapping = BowlBuilderIngredientRecipeMapping(
      id: existing?.id ??
          _idGenerator.nextBowlBuilderIngredientRecipeMappingId(),
      organizationId: organizationId,
      bowlBuilderIngredientId: bowlBuilderIngredientId,
      inventoryIngredientId: inventoryIngredientId,
      quantityPerSelection: quantityPerSelection,
      createdAt: existing?.createdAt ?? performedAt,
      revision: (existing?.revision ?? 0) + 1,
    );
    await _repository.save(mapping);

    await _auditRepository.appendEvent(RecipeAuditEntry(
      id: '${mapping.id}-audit-set-${performedAt.microsecondsSinceEpoch}',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: RecipeAuditEventType.bowlBuilderMappingSet,
      description: 'Bowl Builder ingredient "$bowlBuilderIngredientId" '
          'mapped to inventory ingredient "$inventoryIngredientId"',
      targetEntityId: mapping.id,
      timestamp: performedAt,
    ));

    return mapping;
  }
}
