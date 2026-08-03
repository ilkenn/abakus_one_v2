import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/money.dart';
import '../../../inventory/domain/inventory_unit.dart';
import '../../../inventory/domain/quantity.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/costing_audit_entry_repository.dart';
import '../../data/purchase_price_repository.dart';
import '../../domain/costing_audit_entry.dart';
import '../../domain/costing_audit_event_type.dart';
import '../../domain/purchase_price.dart';
import '../identity/purchase_price_id_generator.dart';

/// Records a new, append-only [PurchasePrice] — admin-only
/// (`PosAuthorizedAction.manageCostingConfiguration`, the brief's own
/// "most sensitive" tier for costing data), Phase 7
/// (`docs/decisions.md` ADR-024). Never edits or removes a prior
/// price — a correction is a new record.
class RecordPurchasePrice {
  const RecordPurchasePrice({
    required PosAuthorizationPolicy authorizationPolicy,
    required PurchasePriceIdGenerator idGenerator,
    required PurchasePriceRepository repository,
    required CostingAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final PurchasePriceIdGenerator _idGenerator;
  final PurchasePriceRepository _repository;
  final CostingAuditEntryRepository _auditRepository;

  Future<PurchasePrice> call({
    required String organizationId,
    required String ingredientId,
    required Money pricePerUnit,
    required InventoryUnit unit,
    required Quantity quantityPurchased,
    String? supplierId,
    required DateTime recordedAt,
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

    if (!quantityPurchased.isPositive) {
      throw NonPositiveQuantityViolation(
        context: 'PurchasePrice.quantityPurchased',
        quantity: quantityPurchased.smallestUnits,
      );
    }

    final price = PurchasePrice(
      id: _idGenerator.nextPurchasePriceId(),
      organizationId: organizationId,
      ingredientId: ingredientId,
      pricePerUnit: pricePerUnit,
      unit: unit,
      quantityPurchased: quantityPurchased,
      supplierId: supplierId,
      recordedAt: recordedAt,
      createdByStaffId: performedByStaffId,
      createdAt: performedAt,
    );
    await _repository.save(price);

    await _auditRepository.appendEvent(CostingAuditEntry(
      id: '${price.id}-audit-recorded',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: CostingAuditEventType.purchasePriceRecorded,
      description: 'Purchase price recorded for ingredient "$ingredientId"',
      targetEntityId: price.id,
      timestamp: performedAt,
    ));

    return price;
  }
}
