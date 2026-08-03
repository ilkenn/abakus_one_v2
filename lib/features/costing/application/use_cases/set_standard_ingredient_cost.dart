import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/money.dart';
import '../../../inventory/domain/inventory_unit.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/costing_audit_entry_repository.dart';
import '../../data/standard_ingredient_cost_repository.dart';
import '../../domain/costing_audit_entry.dart';
import '../../domain/costing_audit_event_type.dart';
import '../../domain/standard_ingredient_cost.dart';
import '../identity/standard_ingredient_cost_id_generator.dart';

/// Creates or updates (upserts by `ingredientId`) a
/// [StandardIngredientCost] — admin-only
/// (`PosAuthorizedAction.manageCostingConfiguration`), Phase 7
/// (`docs/decisions.md` ADR-024).
class SetStandardIngredientCost {
  const SetStandardIngredientCost({
    required PosAuthorizationPolicy authorizationPolicy,
    required StandardIngredientCostIdGenerator idGenerator,
    required StandardIngredientCostRepository repository,
    required CostingAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StandardIngredientCostIdGenerator _idGenerator;
  final StandardIngredientCostRepository _repository;
  final CostingAuditEntryRepository _auditRepository;

  Future<StandardIngredientCost> call({
    required String organizationId,
    required String ingredientId,
    required Money unitCost,
    required InventoryUnit unit,
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

    final existing = await _repository.findByIngredientId(ingredientId);
    final cost = StandardIngredientCost(
      id: existing?.id ?? _idGenerator.nextStandardIngredientCostId(),
      organizationId: organizationId,
      ingredientId: ingredientId,
      unitCost: unitCost,
      unit: unit,
      setByStaffId: performedByStaffId,
      setAt: performedAt,
      revision: (existing?.revision ?? 0) + 1,
    );
    await _repository.save(cost);

    await _auditRepository.appendEvent(CostingAuditEntry(
      id: '${cost.id}-audit-set-${performedAt.microsecondsSinceEpoch}',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: CostingAuditEventType.standardCostSet,
      description: 'Standard cost set for ingredient "$ingredientId"',
      targetEntityId: cost.id,
      timestamp: performedAt,
    ));

    return cost;
  }
}
