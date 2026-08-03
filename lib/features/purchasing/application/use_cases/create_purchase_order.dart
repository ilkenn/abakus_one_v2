import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/purchase_order_line_repository.dart';
import '../../data/purchase_order_repository.dart';
import '../../data/supplier_audit_entry_repository.dart';
import '../../data/supplier_price_repository.dart';
import '../../domain/purchase_order.dart';
import '../../domain/purchase_order_line.dart';
import '../../domain/purchase_order_line_input.dart';
import '../../domain/purchase_order_status.dart';
import '../../domain/supplier_audit_entry.dart';
import '../../domain/supplier_audit_event_type.dart';
import '../identity/purchase_order_id_generator.dart';
import '../identity/purchase_order_line_id_generator.dart';

/// Creates a draft [PurchaseOrder] with its lines — manager+
/// (`PosAuthorizedAction.managePurchasing`), Phase 7
/// (`docs/decisions.md` ADR-024). Each line's
/// [PurchaseOrderLine.unitPriceAtOrder] is snapshotted from the
/// [SupplierProduct]'s most recently recorded [SupplierPrice] at
/// creation time — never a live reference — so a later price change
/// never rewrites this order's recorded cost. Throws
/// [UnknownSupplierEntityViolation] if a supplier product has no
/// price on record yet.
class CreatePurchaseOrder {
  const CreatePurchaseOrder({
    required PosAuthorizationPolicy authorizationPolicy,
    required PurchaseOrderIdGenerator idGenerator,
    required PurchaseOrderLineIdGenerator lineIdGenerator,
    required PurchaseOrderRepository repository,
    required PurchaseOrderLineRepository lineRepository,
    required SupplierPriceRepository priceRepository,
    required SupplierAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _lineIdGenerator = lineIdGenerator,
        _repository = repository,
        _lineRepository = lineRepository,
        _priceRepository = priceRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final PurchaseOrderIdGenerator _idGenerator;
  final PurchaseOrderLineIdGenerator _lineIdGenerator;
  final PurchaseOrderRepository _repository;
  final PurchaseOrderLineRepository _lineRepository;
  final SupplierPriceRepository _priceRepository;
  final SupplierAuditEntryRepository _auditRepository;

  Future<PurchaseOrder> call({
    required String organizationId,
    required String branchId,
    required String supplierId,
    required List<PurchaseOrderLineInput> lines,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.managePurchasing;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final order = PurchaseOrder(
      id: _idGenerator.nextPurchaseOrderId(),
      organizationId: organizationId,
      branchId: branchId,
      supplierId: supplierId,
      status: PurchaseOrderStatus.draft,
      createdByStaffId: performedByStaffId,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(order);

    for (final input in lines) {
      final prices = await _priceRepository
          .findBySupplierProductId(input.supplierProductId);
      if (prices.isEmpty) {
        throw UnknownSupplierEntityViolation(
          entityName: 'SupplierPrice',
          id: input.supplierProductId,
        );
      }
      final latestPrice = prices
          .reduce((a, b) => a.effectiveFrom.isAfter(b.effectiveFrom) ? a : b);

      await _lineRepository.save(PurchaseOrderLine(
        id: _lineIdGenerator.nextPurchaseOrderLineId(),
        purchaseOrderId: order.id,
        supplierProductId: input.supplierProductId,
        orderedQuantity: input.orderedQuantity,
        unitPriceAtOrder: latestPrice.pricePerUnit,
      ));
    }

    await _auditRepository.appendEvent(SupplierAuditEntry(
      id: '${order.id}-audit-created',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: SupplierAuditEventType.purchaseOrderCreated,
      description:
          'Purchase order created for supplier "$supplierId" (${lines.length} line(s))',
      targetEntityId: order.id,
      timestamp: performedAt,
    ));

    return order;
  }
}
