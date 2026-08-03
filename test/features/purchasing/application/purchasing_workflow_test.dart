import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/stock_movement_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/record_stock_movement.dart';
import 'package:abakus_one_v2/features/inventory/data/branch_stock_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/ingredient_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_item_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/stock_movement_repository.dart';
import 'package:abakus_one_v2/features/inventory/domain/ingredient.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_item.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/negative_stock_policy.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/purchasing/application/identity/goods_receipt_id_generator.dart';
import 'package:abakus_one_v2/features/purchasing/application/identity/goods_receipt_line_id_generator.dart';
import 'package:abakus_one_v2/features/purchasing/application/identity/purchase_order_id_generator.dart';
import 'package:abakus_one_v2/features/purchasing/application/identity/purchase_order_line_id_generator.dart';
import 'package:abakus_one_v2/features/purchasing/application/identity/purchase_return_id_generator.dart';
import 'package:abakus_one_v2/features/purchasing/application/identity/supplier_id_generator.dart';
import 'package:abakus_one_v2/features/purchasing/application/identity/supplier_price_id_generator.dart';
import 'package:abakus_one_v2/features/purchasing/application/identity/supplier_product_id_generator.dart';
import 'package:abakus_one_v2/features/purchasing/application/use_cases/create_purchase_order.dart';
import 'package:abakus_one_v2/features/purchasing/application/use_cases/create_supplier.dart';
import 'package:abakus_one_v2/features/purchasing/application/use_cases/create_supplier_product.dart';
import 'package:abakus_one_v2/features/purchasing/application/use_cases/receive_goods.dart';
import 'package:abakus_one_v2/features/purchasing/application/use_cases/record_purchase_return.dart';
import 'package:abakus_one_v2/features/purchasing/application/use_cases/record_supplier_price.dart';
import 'package:abakus_one_v2/features/purchasing/application/use_cases/submit_purchase_order.dart';
import 'package:abakus_one_v2/features/purchasing/data/goods_receipt_line_repository.dart';
import 'package:abakus_one_v2/features/purchasing/data/goods_receipt_repository.dart';
import 'package:abakus_one_v2/features/purchasing/data/purchase_order_line_repository.dart';
import 'package:abakus_one_v2/features/purchasing/data/purchase_order_repository.dart';
import 'package:abakus_one_v2/features/purchasing/data/purchase_return_repository.dart';
import 'package:abakus_one_v2/features/purchasing/data/supplier_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/purchasing/data/supplier_price_repository.dart';
import 'package:abakus_one_v2/features/purchasing/data/supplier_product_repository.dart';
import 'package:abakus_one_v2/features/purchasing/data/supplier_repository.dart';
import 'package:abakus_one_v2/features/purchasing/domain/goods_receipt_line_input.dart';
import 'package:abakus_one_v2/features/purchasing/domain/purchase_order_line_input.dart';
import 'package:abakus_one_v2/features/purchasing/domain/purchase_order_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/purchasing_test_fixtures.dart';

void main() {
  group('Purchasing workflow', () {
    test(
        'create supplier -> product -> price -> order -> submit -> '
        'receive fully increases stock and marks the order received', () async {
      final ingredientRepository = InMemoryIngredientRepository();
      await ingredientRepository.save(Ingredient(
        id: 'ingredient-rice',
        organizationId: 'org-1',
        name: 'Pirinç',
        baseUnit: InventoryUnit.kilogram,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final inventoryItemRepository = InMemoryInventoryItemRepository();
      await inventoryItemRepository.save(InventoryItem(
        id: 'item-rice',
        ingredientId: 'ingredient-rice',
        organizationId: 'org-1',
        trackingUnit: InventoryUnit.kilogram,
        negativeStockPolicy: NegativeStockPolicy.allow,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final supplierRepository = InMemorySupplierRepository();
      final supplier = await CreateSupplier(
        authorizationPolicy: const AllowAllPurchasingPolicy(),
        idGenerator: SequentialSupplierIdGenerator(),
        repository: supplierRepository,
        auditRepository: InMemorySupplierAuditEntryRepository(),
      )(
        organizationId: 'org-1',
        name: 'Toptan Gıda A.Ş.',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final supplierProductRepository = InMemorySupplierProductRepository();
      final supplierProduct = await CreateSupplierProduct(
        authorizationPolicy: const AllowAllPurchasingPolicy(),
        idGenerator: SequentialSupplierProductIdGenerator(),
        repository: supplierProductRepository,
        ingredientRepository: ingredientRepository,
        auditRepository: InMemorySupplierAuditEntryRepository(),
      )(
        organizationId: 'org-1',
        supplierId: supplier.id,
        ingredientId: 'ingredient-rice',
        supplierProductCode: 'RICE-25KG',
        supplierUnit: InventoryUnit.kilogram,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final priceRepository = InMemorySupplierPriceRepository();
      await RecordSupplierPrice(
        authorizationPolicy: const AllowAllPurchasingPolicy(),
        idGenerator: SequentialSupplierPriceIdGenerator(),
        repository: priceRepository,
        auditRepository: InMemorySupplierAuditEntryRepository(),
      )(
        organizationId: 'org-1',
        supplierProductId: supplierProduct.id,
        pricePerUnit: Money.fromWhole(25, Currency.tryLira),
        effectiveFrom: DateTime(2026, 1, 1),
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final orderRepository = InMemoryPurchaseOrderRepository();
      final orderLineRepository = InMemoryPurchaseOrderLineRepository();
      final order = await CreatePurchaseOrder(
        authorizationPolicy: const AllowAllPurchasingPolicy(),
        idGenerator: SequentialPurchaseOrderIdGenerator(),
        lineIdGenerator: SequentialPurchaseOrderLineIdGenerator(),
        repository: orderRepository,
        lineRepository: orderLineRepository,
        priceRepository: priceRepository,
        auditRepository: InMemorySupplierAuditEntryRepository(),
      )(
        organizationId: 'org-1',
        branchId: 'branch-1',
        supplierId: supplier.id,
        lines: [
          PurchaseOrderLineInput(
            supplierProductId: supplierProduct.id,
            orderedQuantity: Quantity.fromWhole(10, InventoryUnit.kilogram),
          ),
        ],
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );
      expect(order.status, PurchaseOrderStatus.draft);

      final submitted = await SubmitPurchaseOrder(
        authorizationPolicy: const AllowAllPurchasingPolicy(),
        repository: orderRepository,
        auditRepository: InMemorySupplierAuditEntryRepository(),
      )(
        purchaseOrderId: order.id,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );
      expect(submitted.status, PurchaseOrderStatus.submitted);

      final orderLines =
          await orderLineRepository.findByPurchaseOrderId(order.id);
      final orderLine = orderLines.single;
      expect(orderLine.unitPriceAtOrder.minorUnits,
          Money.fromWhole(25, Currency.tryLira).minorUnits);

      final branchStockRepository = InMemoryBranchStockRepository();
      final recordStockMovement = RecordStockMovement(
        idGenerator: SequentialStockMovementIdGenerator(),
        movementRepository: InMemoryStockMovementRepository(),
        branchStockRepository: branchStockRepository,
        inventoryItemRepository: inventoryItemRepository,
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );
      final receiptLineRepository = InMemoryGoodsReceiptLineRepository();
      final receive = ReceiveGoods(
        authorizationPolicy: const AllowAllPurchasingPolicy(),
        idGenerator: SequentialGoodsReceiptIdGenerator(),
        lineIdGenerator: SequentialGoodsReceiptLineIdGenerator(),
        purchaseOrderRepository: orderRepository,
        purchaseOrderLineRepository: orderLineRepository,
        supplierProductRepository: supplierProductRepository,
        inventoryItemRepository: inventoryItemRepository,
        recordStockMovement: recordStockMovement,
        receiptRepository: InMemoryGoodsReceiptRepository(),
        receiptLineRepository: receiptLineRepository,
        auditRepository: InMemorySupplierAuditEntryRepository(),
      );

      await receive(
        purchaseOrderId: order.id,
        branchId: 'branch-1',
        locationId: 'location-1',
        lines: [
          GoodsReceiptLineInput(
            purchaseOrderLineId: orderLine.id,
            receivedQuantity: Quantity.fromWhole(10, InventoryUnit.kilogram),
          ),
        ],
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 3),
      );

      final balance = await branchStockRepository.findByItemAndLocation(
          'item-rice', 'location-1');
      expect(balance!.quantityOnHand.smallestUnits, 10000);

      final finalOrder = await orderRepository.findById(order.id);
      expect(finalOrder!.status, PurchaseOrderStatus.received);
    });

    test(
        'receiving less than ordered marks the order partiallyReceived, '
        'and records the exact under-received quantity', () async {
      final inventoryItemRepository = InMemoryInventoryItemRepository();
      await inventoryItemRepository.save(InventoryItem(
        id: 'item-rice',
        ingredientId: 'ingredient-rice',
        organizationId: 'org-1',
        trackingUnit: InventoryUnit.kilogram,
        negativeStockPolicy: NegativeStockPolicy.allow,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final orderRepository = InMemoryPurchaseOrderRepository();
      final orderLineRepository = InMemoryPurchaseOrderLineRepository();
      final priceRepository = InMemorySupplierPriceRepository();
      await RecordSupplierPrice(
        authorizationPolicy: const AllowAllPurchasingPolicy(),
        idGenerator: SequentialSupplierPriceIdGenerator(),
        repository: priceRepository,
        auditRepository: InMemorySupplierAuditEntryRepository(),
      )(
        organizationId: 'org-1',
        supplierProductId: 'supplier-product-1',
        pricePerUnit: Money.fromWhole(25, Currency.tryLira),
        effectiveFrom: DateTime(2026, 1, 1),
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final order = await CreatePurchaseOrder(
        authorizationPolicy: const AllowAllPurchasingPolicy(),
        idGenerator: SequentialPurchaseOrderIdGenerator(),
        lineIdGenerator: SequentialPurchaseOrderLineIdGenerator(),
        repository: orderRepository,
        lineRepository: orderLineRepository,
        priceRepository: priceRepository,
        auditRepository: InMemorySupplierAuditEntryRepository(),
      )(
        organizationId: 'org-1',
        branchId: 'branch-1',
        supplierId: 'supplier-1',
        lines: [
          PurchaseOrderLineInput(
            supplierProductId: 'supplier-product-1',
            orderedQuantity: Quantity.fromWhole(10, InventoryUnit.kilogram),
          ),
        ],
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );
      await SubmitPurchaseOrder(
        authorizationPolicy: const AllowAllPurchasingPolicy(),
        repository: orderRepository,
        auditRepository: InMemorySupplierAuditEntryRepository(),
      )(
        purchaseOrderId: order.id,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );
      final orderLine =
          (await orderLineRepository.findByPurchaseOrderId(order.id)).single;

      final supplierProductRepository = InMemorySupplierProductRepository();
      // No SupplierProduct saved -> stock movement step is skipped
      // honestly, but the receipt line itself is still recorded.
      final receiptLineRepository = InMemoryGoodsReceiptLineRepository();
      final receive = ReceiveGoods(
        authorizationPolicy: const AllowAllPurchasingPolicy(),
        idGenerator: SequentialGoodsReceiptIdGenerator(),
        lineIdGenerator: SequentialGoodsReceiptLineIdGenerator(),
        purchaseOrderRepository: orderRepository,
        purchaseOrderLineRepository: orderLineRepository,
        supplierProductRepository: supplierProductRepository,
        inventoryItemRepository: inventoryItemRepository,
        recordStockMovement: RecordStockMovement(
          idGenerator: SequentialStockMovementIdGenerator(),
          movementRepository: InMemoryStockMovementRepository(),
          branchStockRepository: InMemoryBranchStockRepository(),
          inventoryItemRepository: inventoryItemRepository,
          auditRepository: InMemoryInventoryAuditEntryRepository(),
        ),
        receiptRepository: InMemoryGoodsReceiptRepository(),
        receiptLineRepository: receiptLineRepository,
        auditRepository: InMemorySupplierAuditEntryRepository(),
      );

      await receive(
        purchaseOrderId: order.id,
        branchId: 'branch-1',
        locationId: 'location-1',
        lines: [
          GoodsReceiptLineInput(
            purchaseOrderLineId: orderLine.id,
            receivedQuantity: Quantity.fromWhole(4, InventoryUnit.kilogram),
          ),
        ],
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 3),
      );

      final finalOrder = await orderRepository.findById(order.id);
      expect(finalOrder!.status, PurchaseOrderStatus.partiallyReceived);

      final recordedLines =
          await receiptLineRepository.findByPurchaseOrderLineId(orderLine.id);
      expect(recordedLines.single.receivedQuantity.smallestUnits, 4000);
    });

    test('an unauthorized actor is denied creating a supplier', () async {
      final useCase = CreateSupplier(
        authorizationPolicy: const DenyAllPurchasingPolicy(),
        idGenerator: SequentialSupplierIdGenerator(),
        repository: InMemorySupplierRepository(),
        auditRepository: InMemorySupplierAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          name: 'Test',
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('RecordPurchaseReturn', () {
    test('requires a non-empty reason', () async {
      final useCase = RecordPurchaseReturn(
        authorizationPolicy: const AllowAllPurchasingPolicy(),
        idGenerator: SequentialPurchaseReturnIdGenerator(),
        repository: InMemoryPurchaseReturnRepository(),
        auditRepository: InMemorySupplierAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          branchId: 'branch-1',
          supplierId: 'supplier-1',
          goodsReceiptLineId: 'receipt-line-1',
          returnedQuantity: Quantity.fromWhole(1, InventoryUnit.kilogram),
          reason: '  ',
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<InventoryReasonRequiredViolation>()),
      );
    });
  });
}
