import '../../../../core/errors/business_rule_violation.dart';
import '../../../inventory/application/use_cases/record_stock_movement.dart';
import '../../../inventory/data/inventory_item_repository.dart';
import '../../../inventory/domain/stock_movement_type.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/goods_receipt_line_repository.dart';
import '../../data/goods_receipt_repository.dart';
import '../../data/purchase_order_line_repository.dart';
import '../../data/purchase_order_repository.dart';
import '../../data/supplier_audit_entry_repository.dart';
import '../../data/supplier_product_repository.dart';
import '../../domain/goods_receipt.dart';
import '../../domain/goods_receipt_line.dart';
import '../../domain/goods_receipt_line_input.dart';
import '../../domain/purchase_order_status.dart';
import '../../domain/supplier_audit_entry.dart';
import '../../domain/supplier_audit_event_type.dart';
import '../identity/goods_receipt_id_generator.dart';
import '../identity/goods_receipt_line_id_generator.dart';

/// Records a [GoodsReceipt] against a submitted (or already partially
/// received) [PurchaseOrder], increases stock for every receipt line
/// whose unit matches its [InventoryItem]'s tracking unit, and derives
/// the order's new [PurchaseOrderStatus] from how much of each line
/// has been received in total — manager+
/// (`PosAuthorizedAction.managePurchasing`), Phase 7
/// (`docs/decisions.md` ADR-024).
///
/// [GoodsReceiptLine.receivedQuantity] is always recorded exactly as
/// given, even when it's more or less than ordered — "partial
/// receipt, over/under receipt" is an honest fact, never silently
/// corrected. A line whose ingredient has no `InventoryItem` tracking
/// it yet, or whose received unit doesn't match the tracking unit, is
/// still recorded here but its stock movement is skipped — the same
/// honest cross-unit limitation every other Phase 7 aggregator
/// documents.
class ReceiveGoods {
  const ReceiveGoods({
    required PosAuthorizationPolicy authorizationPolicy,
    required GoodsReceiptIdGenerator idGenerator,
    required GoodsReceiptLineIdGenerator lineIdGenerator,
    required PurchaseOrderRepository purchaseOrderRepository,
    required PurchaseOrderLineRepository purchaseOrderLineRepository,
    required SupplierProductRepository supplierProductRepository,
    required InventoryItemRepository inventoryItemRepository,
    required RecordStockMovement recordStockMovement,
    required GoodsReceiptRepository receiptRepository,
    required GoodsReceiptLineRepository receiptLineRepository,
    required SupplierAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _lineIdGenerator = lineIdGenerator,
        _purchaseOrderRepository = purchaseOrderRepository,
        _purchaseOrderLineRepository = purchaseOrderLineRepository,
        _supplierProductRepository = supplierProductRepository,
        _inventoryItemRepository = inventoryItemRepository,
        _recordStockMovement = recordStockMovement,
        _receiptRepository = receiptRepository,
        _receiptLineRepository = receiptLineRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final GoodsReceiptIdGenerator _idGenerator;
  final GoodsReceiptLineIdGenerator _lineIdGenerator;
  final PurchaseOrderRepository _purchaseOrderRepository;
  final PurchaseOrderLineRepository _purchaseOrderLineRepository;
  final SupplierProductRepository _supplierProductRepository;
  final InventoryItemRepository _inventoryItemRepository;
  final RecordStockMovement _recordStockMovement;
  final GoodsReceiptRepository _receiptRepository;
  final GoodsReceiptLineRepository _receiptLineRepository;
  final SupplierAuditEntryRepository _auditRepository;

  Future<GoodsReceipt> call({
    required String purchaseOrderId,
    required String branchId,
    required String locationId,
    required List<GoodsReceiptLineInput> lines,
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

    final order = await _purchaseOrderRepository.findById(purchaseOrderId);
    if (order == null) {
      throw UnknownSupplierEntityViolation(
        entityName: 'PurchaseOrder',
        id: purchaseOrderId,
      );
    }
    if (order.status != PurchaseOrderStatus.submitted &&
        order.status != PurchaseOrderStatus.partiallyReceived) {
      throw InvalidPurchaseOrderTransitionViolation(
        fromStatusName: order.status.name,
        toStatusName: PurchaseOrderStatus.partiallyReceived.name,
      );
    }

    final receipt = GoodsReceipt(
      id: _idGenerator.nextGoodsReceiptId(),
      purchaseOrderId: purchaseOrderId,
      branchId: branchId,
      locationId: locationId,
      receivedByStaffId: performedByStaffId,
      receivedAt: performedAt,
      createdAt: performedAt,
    );
    await _receiptRepository.save(receipt);

    for (final input in lines) {
      final orderLine = await _purchaseOrderLineRepository
          .findById(input.purchaseOrderLineId);
      if (orderLine == null || orderLine.purchaseOrderId != purchaseOrderId) {
        throw UnknownSupplierEntityViolation(
          entityName: 'PurchaseOrderLine',
          id: input.purchaseOrderLineId,
        );
      }

      await _receiptLineRepository.save(GoodsReceiptLine(
        id: _lineIdGenerator.nextGoodsReceiptLineId(),
        goodsReceiptId: receipt.id,
        purchaseOrderLineId: input.purchaseOrderLineId,
        supplierProductId: orderLine.supplierProductId,
        receivedQuantity: input.receivedQuantity,
      ));

      final supplierProduct = await _supplierProductRepository
          .findById(orderLine.supplierProductId);
      if (supplierProduct == null) continue;

      final inventoryItem = await _inventoryItemRepository
          .findByIngredientId(supplierProduct.ingredientId);
      if (inventoryItem == null) continue;
      if (inventoryItem.trackingUnit != input.receivedQuantity.unit) continue;

      await _recordStockMovement(
        branchId: branchId,
        inventoryItemId: inventoryItem.id,
        locationId: locationId,
        type: StockMovementType.receipt,
        quantityDelta: input.receivedQuantity,
        idempotencyKey: '${receipt.id}-${orderLine.id}',
        performedByStaffId: performedByStaffId,
        occurredAt: performedAt,
        correlationId: purchaseOrderId,
      );
    }

    final allOrderLines = await _purchaseOrderLineRepository
        .findByPurchaseOrderId(purchaseOrderId);
    var allFullyReceived = allOrderLines.isNotEmpty;
    var anyReceived = false;
    for (final orderLine in allOrderLines) {
      final receivedForLine =
          await _receiptLineRepository.findByPurchaseOrderLineId(orderLine.id);
      final totalReceivedSmallestUnits = receivedForLine
          .where(
              (l) => l.receivedQuantity.unit == orderLine.orderedQuantity.unit)
          .fold<int>(0, (sum, l) => sum + l.receivedQuantity.smallestUnits);
      if (totalReceivedSmallestUnits > 0) anyReceived = true;
      if (totalReceivedSmallestUnits <
          orderLine.orderedQuantity.smallestUnits) {
        allFullyReceived = false;
      }
    }

    final newStatus = allFullyReceived
        ? PurchaseOrderStatus.received
        : (anyReceived ? PurchaseOrderStatus.partiallyReceived : order.status);
    await _purchaseOrderRepository.save(order.copyWith(
      status: newStatus,
      revision: order.revision + 1,
    ));

    await _auditRepository.appendEvent(SupplierAuditEntry(
      id: '${receipt.id}-audit-received',
      organizationId: order.organizationId,
      actorId: performedByStaffId,
      type: SupplierAuditEventType.goodsReceived,
      description:
          'Goods received for purchase order "$purchaseOrderId" (${lines.length} line(s))',
      targetEntityId: receipt.id,
      timestamp: performedAt,
    ));

    return receipt;
  }
}
