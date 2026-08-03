import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/stock_movement_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/record_stock_movement.dart';
import 'package:abakus_one_v2/features/inventory/data/branch_stock_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_item_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/stock_movement_repository.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_item.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/negative_stock_policy.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_version_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/sub_recipe_repository.dart';
import 'package:abakus_one_v2/features/recipes/data/sub_recipe_version_repository.dart';
import 'package:abakus_one_v2/features/recipes/domain/portion_definition.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_line.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_version.dart';
import 'package:abakus_one_v2/features/recipes/domain/yield.dart';
import 'package:abakus_one_v2/features/stock_consumption/application/identity/stock_consumption_record_id_generator.dart';
import 'package:abakus_one_v2/features/stock_consumption/application/use_cases/consume_stock_for_order.dart';
import 'package:abakus_one_v2/features/stock_consumption/application/use_cases/reverse_stock_consumption.dart';
import 'package:abakus_one_v2/features/stock_consumption/data/stock_consumption_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/stock_consumption/data/stock_consumption_record_repository.dart';
import 'package:abakus_one_v2/features/stock_consumption/domain/order_line_recipe_reference.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/stock_consumption_test_fixtures.dart';

void main() {
  group('ConsumeStockForOrder', () {
    test(
        'deducts stock for the historical recipe version, scaled by '
        'ordered quantity', () async {
      final versionRepository = InMemoryRecipeVersionRepository();
      final version = RecipeVersion(
        id: 'version-1',
        recipeId: 'recipe-1',
        versionNumber: 1,
        lines: [
          RecipeLine(
            id: 'line-1',
            ingredientId: 'chicken',
            quantity: Quantity.fromWhole(150, InventoryUnit.gram),
          ),
        ],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldAmount: Yield(
          totalQuantity: Quantity.fromWhole(150, InventoryUnit.gram),
          portionCount: 1,
        ),
        createdAt: DateTime(2026, 1, 1),
        createdByStaffId: 'manager-1',
      );
      await versionRepository.save(version);

      final inventoryItemRepository = InMemoryInventoryItemRepository();
      await inventoryItemRepository.save(InventoryItem(
        id: 'item-chicken',
        ingredientId: 'chicken',
        organizationId: 'org-1',
        trackingUnit: InventoryUnit.gram,
        negativeStockPolicy: NegativeStockPolicy.allow,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final branchStockRepository = InMemoryBranchStockRepository();
      final recordStockMovement = RecordStockMovement(
        idGenerator: SequentialStockMovementIdGenerator(),
        movementRepository: InMemoryStockMovementRepository(),
        branchStockRepository: branchStockRepository,
        inventoryItemRepository: inventoryItemRepository,
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      final useCase = ConsumeStockForOrder(
        recipeVersionRepository: versionRepository,
        subRecipeRepository: InMemorySubRecipeRepository(),
        subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        inventoryItemRepository: inventoryItemRepository,
        recordStockMovement: recordStockMovement,
        idGenerator: SequentialStockConsumptionRecordIdGenerator(),
        recordRepository: InMemoryStockConsumptionRecordRepository(),
        auditRepository: InMemoryStockConsumptionAuditEntryRepository(),
      );

      await useCase(
        orderId: 'order-1',
        branchId: 'branch-1',
        locationId: 'location-1',
        lines: [
          const OrderLineRecipeReference(
            orderLineId: 'line-a',
            recipeId: 'recipe-1',
            recipeVersionId: 'version-1',
            orderedQuantity: 2,
          ),
        ],
        performedByStaffId: 'system',
        performedAt: DateTime(2026, 1, 2),
      );

      final balance = await branchStockRepository.findByItemAndLocation(
          'item-chicken', 'location-1');
      // 150g * 2 ordered = 300g consumed.
      expect(balance!.quantityOnHand.smallestUnits, -300);
    });

    test('a repeated call for the same order line never deducts twice',
        () async {
      final versionRepository = InMemoryRecipeVersionRepository();
      final version = RecipeVersion(
        id: 'version-1',
        recipeId: 'recipe-1',
        versionNumber: 1,
        lines: [
          RecipeLine(
            id: 'line-1',
            ingredientId: 'chicken',
            quantity: Quantity.fromWhole(100, InventoryUnit.gram),
          ),
        ],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldAmount: Yield(
          totalQuantity: Quantity.fromWhole(100, InventoryUnit.gram),
          portionCount: 1,
        ),
        createdAt: DateTime(2026, 1, 1),
        createdByStaffId: 'manager-1',
      );
      await versionRepository.save(version);

      final inventoryItemRepository = InMemoryInventoryItemRepository();
      await inventoryItemRepository.save(InventoryItem(
        id: 'item-chicken',
        ingredientId: 'chicken',
        organizationId: 'org-1',
        trackingUnit: InventoryUnit.gram,
        negativeStockPolicy: NegativeStockPolicy.allow,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final branchStockRepository = InMemoryBranchStockRepository();
      final recordStockMovement = RecordStockMovement(
        idGenerator: SequentialStockMovementIdGenerator(),
        movementRepository: InMemoryStockMovementRepository(),
        branchStockRepository: branchStockRepository,
        inventoryItemRepository: inventoryItemRepository,
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      final useCase = ConsumeStockForOrder(
        recipeVersionRepository: versionRepository,
        subRecipeRepository: InMemorySubRecipeRepository(),
        subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        inventoryItemRepository: inventoryItemRepository,
        recordStockMovement: recordStockMovement,
        idGenerator: SequentialStockConsumptionRecordIdGenerator(),
        recordRepository: InMemoryStockConsumptionRecordRepository(),
        auditRepository: InMemoryStockConsumptionAuditEntryRepository(),
      );

      final lines = [
        const OrderLineRecipeReference(
          orderLineId: 'line-a',
          recipeId: 'recipe-1',
          recipeVersionId: 'version-1',
          orderedQuantity: 1,
        ),
      ];

      await useCase(
        orderId: 'order-1',
        branchId: 'branch-1',
        locationId: 'location-1',
        lines: lines,
        performedByStaffId: 'system',
        performedAt: DateTime(2026, 1, 2),
      );
      await useCase(
        orderId: 'order-1',
        branchId: 'branch-1',
        locationId: 'location-1',
        lines: lines,
        performedByStaffId: 'system',
        performedAt: DateTime(2026, 1, 2),
      );

      final balance = await branchStockRepository.findByItemAndLocation(
          'item-chicken', 'location-1');
      expect(balance!.quantityOnHand.smallestUnits, -100);
    });
  });

  group('ReverseStockConsumption', () {
    test(
        'restores exactly what was consumed via an equal-and-opposite '
        'movement, and rejects a second reversal', () async {
      final versionRepository = InMemoryRecipeVersionRepository();
      final version = RecipeVersion(
        id: 'version-1',
        recipeId: 'recipe-1',
        versionNumber: 1,
        lines: [
          RecipeLine(
            id: 'line-1',
            ingredientId: 'chicken',
            quantity: Quantity.fromWhole(100, InventoryUnit.gram),
          ),
        ],
        portionDefinition: PortionDefinition(
          quantity: Quantity.fromWhole(1, InventoryUnit.portion),
        ),
        yieldAmount: Yield(
          totalQuantity: Quantity.fromWhole(100, InventoryUnit.gram),
          portionCount: 1,
        ),
        createdAt: DateTime(2026, 1, 1),
        createdByStaffId: 'manager-1',
      );
      await versionRepository.save(version);

      final inventoryItemRepository = InMemoryInventoryItemRepository();
      await inventoryItemRepository.save(InventoryItem(
        id: 'item-chicken',
        ingredientId: 'chicken',
        organizationId: 'org-1',
        trackingUnit: InventoryUnit.gram,
        negativeStockPolicy: NegativeStockPolicy.allow,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final branchStockRepository = InMemoryBranchStockRepository();
      final movementRepository = InMemoryStockMovementRepository();
      final recordStockMovement = RecordStockMovement(
        idGenerator: SequentialStockMovementIdGenerator(),
        movementRepository: movementRepository,
        branchStockRepository: branchStockRepository,
        inventoryItemRepository: inventoryItemRepository,
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      final recordRepository = InMemoryStockConsumptionRecordRepository();
      final consume = ConsumeStockForOrder(
        recipeVersionRepository: versionRepository,
        subRecipeRepository: InMemorySubRecipeRepository(),
        subRecipeVersionRepository: InMemorySubRecipeVersionRepository(),
        inventoryItemRepository: inventoryItemRepository,
        recordStockMovement: recordStockMovement,
        idGenerator: SequentialStockConsumptionRecordIdGenerator(),
        recordRepository: recordRepository,
        auditRepository: InMemoryStockConsumptionAuditEntryRepository(),
      );
      await consume(
        orderId: 'order-1',
        branchId: 'branch-1',
        locationId: 'location-1',
        lines: [
          const OrderLineRecipeReference(
            orderLineId: 'line-a',
            recipeId: 'recipe-1',
            recipeVersionId: 'version-1',
            orderedQuantity: 1,
          ),
        ],
        performedByStaffId: 'system',
        performedAt: DateTime(2026, 1, 2),
      );

      final balanceAfterConsume = await branchStockRepository
          .findByItemAndLocation('item-chicken', 'location-1');
      expect(balanceAfterConsume!.quantityOnHand.smallestUnits, -100);

      final reverse = ReverseStockConsumption(
        authorizationPolicy: const AllowAllStockConsumptionPolicy(),
        movementRepository: movementRepository,
        recordStockMovement: recordStockMovement,
        recordRepository: recordRepository,
        auditRepository: InMemoryStockConsumptionAuditEntryRepository(),
      );

      final reversed = await reverse(
        orderLineId: 'line-a',
        reason: 'Hazırlık öncesi hatalı sipariş, iade edildi',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 3),
      );
      expect(reversed.reversedAt, isNotNull);

      final balanceAfterReversal = await branchStockRepository
          .findByItemAndLocation('item-chicken', 'location-1');
      expect(balanceAfterReversal!.quantityOnHand.smallestUnits, 0);

      expect(
        () => reverse(
          orderLineId: 'line-a',
          reason: 'Tekrar deneme',
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 4),
        ),
        throwsA(isA<StockConsumptionAlreadyReversedViolation>()),
      );
    });

    test('an empty reason throws', () async {
      final reverse = ReverseStockConsumption(
        authorizationPolicy: const AllowAllStockConsumptionPolicy(),
        movementRepository: InMemoryStockMovementRepository(),
        recordStockMovement: RecordStockMovement(
          idGenerator: SequentialStockMovementIdGenerator(),
          movementRepository: InMemoryStockMovementRepository(),
          branchStockRepository: InMemoryBranchStockRepository(),
          inventoryItemRepository: InMemoryInventoryItemRepository(),
          auditRepository: InMemoryInventoryAuditEntryRepository(),
        ),
        recordRepository: InMemoryStockConsumptionRecordRepository(),
        auditRepository: InMemoryStockConsumptionAuditEntryRepository(),
      );

      expect(
        () => reverse(
          orderLineId: 'line-a',
          reason: '   ',
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<InventoryReasonRequiredViolation>()),
      );
    });

    test('an unauthorized actor is denied', () async {
      final reverse = ReverseStockConsumption(
        authorizationPolicy: const DenyAllStockConsumptionPolicy(),
        movementRepository: InMemoryStockMovementRepository(),
        recordStockMovement: RecordStockMovement(
          idGenerator: SequentialStockMovementIdGenerator(),
          movementRepository: InMemoryStockMovementRepository(),
          branchStockRepository: InMemoryBranchStockRepository(),
          inventoryItemRepository: InMemoryInventoryItemRepository(),
          auditRepository: InMemoryInventoryAuditEntryRepository(),
        ),
        recordRepository: InMemoryStockConsumptionRecordRepository(),
        auditRepository: InMemoryStockConsumptionAuditEntryRepository(),
      );

      expect(
        () => reverse(
          orderLineId: 'line-a',
          reason: 'Test',
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
