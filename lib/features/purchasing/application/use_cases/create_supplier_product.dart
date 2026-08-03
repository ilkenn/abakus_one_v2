import '../../../../core/errors/business_rule_violation.dart';
import '../../../inventory/data/ingredient_repository.dart';
import '../../../inventory/domain/inventory_unit.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/supplier_audit_entry_repository.dart';
import '../../data/supplier_product_repository.dart';
import '../../domain/supplier_audit_entry.dart';
import '../../domain/supplier_audit_event_type.dart';
import '../../domain/supplier_product.dart';
import '../identity/supplier_product_id_generator.dart';

/// Maps a [Supplier]'s product to an inventory [Ingredient] — manager+
/// (`PosAuthorizedAction.manageSuppliers`), Phase 7
/// (`docs/decisions.md` ADR-024). Throws
/// [UnknownInventoryEntityViolation] if [ingredientId] doesn't exist.
class CreateSupplierProduct {
  const CreateSupplierProduct({
    required PosAuthorizationPolicy authorizationPolicy,
    required SupplierProductIdGenerator idGenerator,
    required SupplierProductRepository repository,
    required IngredientRepository ingredientRepository,
    required SupplierAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _ingredientRepository = ingredientRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final SupplierProductIdGenerator _idGenerator;
  final SupplierProductRepository _repository;
  final IngredientRepository _ingredientRepository;
  final SupplierAuditEntryRepository _auditRepository;

  Future<SupplierProduct> call({
    required String organizationId,
    required String supplierId,
    required String ingredientId,
    required String supplierProductCode,
    required InventoryUnit supplierUnit,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageSuppliers;
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

    final product = SupplierProduct(
      id: _idGenerator.nextSupplierProductId(),
      organizationId: organizationId,
      supplierId: supplierId,
      ingredientId: ingredientId,
      supplierProductCode: supplierProductCode,
      supplierUnit: supplierUnit,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(product);

    await _auditRepository.appendEvent(SupplierAuditEntry(
      id: '${product.id}-audit-created',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: SupplierAuditEventType.supplierProductCreated,
      description: 'Supplier product "$supplierProductCode" mapped to '
          'ingredient "$ingredientId"',
      targetEntityId: product.id,
      timestamp: performedAt,
    ));

    return product;
  }
}
