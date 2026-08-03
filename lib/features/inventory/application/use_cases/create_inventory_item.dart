import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/ingredient_repository.dart';
import '../../data/inventory_audit_entry_repository.dart';
import '../../data/inventory_item_repository.dart';
import '../../domain/inventory_audit_entry.dart';
import '../../domain/inventory_audit_event_type.dart';
import '../../domain/inventory_item.dart';
import '../../domain/inventory_unit.dart';
import '../../domain/negative_stock_policy.dart';
import '../../domain/quantity.dart';
import '../identity/inventory_item_id_generator.dart';

/// Begins tracking an [Ingredient] in inventory — manager+
/// (`PosAuthorizedAction.manageInventory`). Throws
/// [UnknownInventoryEntityViolation] if [ingredientId] doesn't exist.
class CreateInventoryItem {
  const CreateInventoryItem({
    required PosAuthorizationPolicy authorizationPolicy,
    required InventoryItemIdGenerator idGenerator,
    required InventoryItemRepository repository,
    required IngredientRepository ingredientRepository,
    required InventoryAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _ingredientRepository = ingredientRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final InventoryItemIdGenerator _idGenerator;
  final InventoryItemRepository _repository;
  final IngredientRepository _ingredientRepository;
  final InventoryAuditEntryRepository _auditRepository;

  Future<InventoryItem> call({
    required String ingredientId,
    required InventoryUnit trackingUnit,
    Quantity? reorderThreshold,
    NegativeStockPolicy negativeStockPolicy = NegativeStockPolicy.forbid,
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

    final ingredient = await _ingredientRepository.findById(ingredientId);
    if (ingredient == null) {
      throw UnknownInventoryEntityViolation(
        entityName: 'Ingredient',
        id: ingredientId,
      );
    }

    final item = InventoryItem(
      id: _idGenerator.nextInventoryItemId(),
      ingredientId: ingredientId,
      organizationId: ingredient.organizationId,
      trackingUnit: trackingUnit,
      reorderThreshold: reorderThreshold,
      negativeStockPolicy: negativeStockPolicy,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(item);

    await _auditRepository.appendEvent(InventoryAuditEntry(
      id: '${item.id}-audit-created',
      branchId: null,
      actorId: performedByStaffId,
      type: InventoryAuditEventType.inventoryItemCreated,
      description: 'Inventory item created for ingredient "$ingredientId"',
      targetEntityId: item.id,
      timestamp: performedAt,
    ));

    return item;
  }
}
