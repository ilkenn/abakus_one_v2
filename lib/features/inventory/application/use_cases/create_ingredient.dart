import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/ingredient_repository.dart';
import '../../domain/ingredient.dart';
import '../../domain/inventory_unit.dart';
import '../identity/ingredient_id_generator.dart';

/// Creates an [Ingredient] — manager+
/// (`PosAuthorizedAction.manageInventory`). Always tenant-scoped —
/// "no global mutable ingredient shared across unrelated tenants."
class CreateIngredient {
  const CreateIngredient({
    required PosAuthorizationPolicy authorizationPolicy,
    required IngredientIdGenerator idGenerator,
    required IngredientRepository repository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final IngredientIdGenerator _idGenerator;
  final IngredientRepository _repository;

  Future<Ingredient> call({
    required String organizationId,
    required String name,
    String? category,
    required InventoryUnit baseUnit,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageInventory;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final ingredient = Ingredient(
      id: _idGenerator.nextIngredientId(),
      organizationId: organizationId,
      name: name,
      category: category,
      baseUnit: baseUnit,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(ingredient);
    return ingredient;
  }
}
