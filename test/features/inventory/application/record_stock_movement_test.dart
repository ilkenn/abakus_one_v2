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
import 'package:abakus_one_v2/features/inventory/domain/stock_movement_type.dart';
import 'package:flutter_test/flutter_test.dart';

InventoryItem _buildItem({
  String id = 'item-1',
  NegativeStockPolicy negativeStockPolicy = NegativeStockPolicy.forbid,
}) {
  return InventoryItem(
    id: id,
    ingredientId: 'ingredient-1',
    organizationId: 'org-1',
    trackingUnit: InventoryUnit.gram,
    negativeStockPolicy: negativeStockPolicy,
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

void main() {
  group('RecordStockMovement', () {
    test('a receipt increases on-hand quantity', () async {
      final itemRepository = InMemoryInventoryItemRepository();
      await itemRepository.save(_buildItem());
      final useCase = RecordStockMovement(
        idGenerator: SequentialStockMovementIdGenerator(),
        movementRepository: InMemoryStockMovementRepository(),
        branchStockRepository: InMemoryBranchStockRepository(),
        inventoryItemRepository: itemRepository,
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      final balance = await useCase(
        branchId: 'branch-1',
        inventoryItemId: 'item-1',
        locationId: 'location-1',
        type: StockMovementType.receipt,
        quantityDelta: Quantity.fromWhole(5000, InventoryUnit.gram),
        idempotencyKey: 'key-1',
        performedByStaffId: 'manager-1',
        occurredAt: DateTime(2026, 1, 1),
      );

      expect(balance.quantityOnHand.smallestUnits, 5000);
    });

    test('a duplicate idempotencyKey never deducts twice', () async {
      final itemRepository = InMemoryInventoryItemRepository();
      await itemRepository.save(_buildItem());
      final useCase = RecordStockMovement(
        idGenerator: SequentialStockMovementIdGenerator(),
        movementRepository: InMemoryStockMovementRepository(),
        branchStockRepository: InMemoryBranchStockRepository(),
        inventoryItemRepository: itemRepository,
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );
      Future<dynamic> call() => useCase(
            branchId: 'branch-1',
            inventoryItemId: 'item-1',
            locationId: 'location-1',
            type: StockMovementType.consumption,
            quantityDelta: Quantity.fromWhole(-100, InventoryUnit.gram),
            idempotencyKey: 'same-key',
            performedByStaffId: 'manager-1',
            occurredAt: DateTime(2026, 1, 1),
          );

      // Seed enough stock first.
      await useCase(
        branchId: 'branch-1',
        inventoryItemId: 'item-1',
        locationId: 'location-1',
        type: StockMovementType.receipt,
        quantityDelta: Quantity.fromWhole(1000, InventoryUnit.gram),
        idempotencyKey: 'receipt-1',
        performedByStaffId: 'manager-1',
        occurredAt: DateTime(2026, 1, 1),
      );

      final first = await call();
      final second = await call();

      expect(first.quantityOnHand, second.quantityOnHand);
      expect(second.quantityOnHand.smallestUnits, 900);
    });

    test('forbid policy throws NegativeStockNotAllowedViolation', () async {
      final itemRepository = InMemoryInventoryItemRepository();
      await itemRepository.save(_buildItem());
      final useCase = RecordStockMovement(
        idGenerator: SequentialStockMovementIdGenerator(),
        movementRepository: InMemoryStockMovementRepository(),
        branchStockRepository: InMemoryBranchStockRepository(),
        inventoryItemRepository: itemRepository,
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      expect(
        () => useCase(
          branchId: 'branch-1',
          inventoryItemId: 'item-1',
          locationId: 'location-1',
          type: StockMovementType.consumption,
          quantityDelta: Quantity.fromWhole(-100, InventoryUnit.gram),
          idempotencyKey: 'key-1',
          performedByStaffId: 'manager-1',
          occurredAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<NegativeStockNotAllowedViolation>()),
      );
    });

    test('allow policy permits negative on-hand quantity', () async {
      final itemRepository = InMemoryInventoryItemRepository();
      await itemRepository.save(
        _buildItem(negativeStockPolicy: NegativeStockPolicy.allow),
      );
      final useCase = RecordStockMovement(
        idGenerator: SequentialStockMovementIdGenerator(),
        movementRepository: InMemoryStockMovementRepository(),
        branchStockRepository: InMemoryBranchStockRepository(),
        inventoryItemRepository: itemRepository,
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      final balance = await useCase(
        branchId: 'branch-1',
        inventoryItemId: 'item-1',
        locationId: 'location-1',
        type: StockMovementType.consumption,
        quantityDelta: Quantity.fromWhole(-100, InventoryUnit.gram),
        idempotencyKey: 'key-1',
        performedByStaffId: 'manager-1',
        occurredAt: DateTime(2026, 1, 1),
      );

      expect(balance.quantityOnHand.isNegative, isTrue);
    });

    test('warn policy applies the movement and flags the balance', () async {
      final itemRepository = InMemoryInventoryItemRepository();
      await itemRepository.save(
        _buildItem(negativeStockPolicy: NegativeStockPolicy.warn),
      );
      final useCase = RecordStockMovement(
        idGenerator: SequentialStockMovementIdGenerator(),
        movementRepository: InMemoryStockMovementRepository(),
        branchStockRepository: InMemoryBranchStockRepository(),
        inventoryItemRepository: itemRepository,
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      final balance = await useCase(
        branchId: 'branch-1',
        inventoryItemId: 'item-1',
        locationId: 'location-1',
        type: StockMovementType.consumption,
        quantityDelta: Quantity.fromWhole(-100, InventoryUnit.gram),
        idempotencyKey: 'key-1',
        performedByStaffId: 'manager-1',
        occurredAt: DateTime(2026, 1, 1),
      );

      expect(balance.isNegativeStockWarning, isTrue);
    });

    test('an unknown inventory item throws', () async {
      final useCase = RecordStockMovement(
        idGenerator: SequentialStockMovementIdGenerator(),
        movementRepository: InMemoryStockMovementRepository(),
        branchStockRepository: InMemoryBranchStockRepository(),
        inventoryItemRepository: InMemoryInventoryItemRepository(),
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      expect(
        () => useCase(
          branchId: 'branch-1',
          inventoryItemId: 'missing',
          locationId: 'location-1',
          type: StockMovementType.receipt,
          quantityDelta: Quantity.fromWhole(100, InventoryUnit.gram),
          idempotencyKey: 'key-1',
          performedByStaffId: 'manager-1',
          occurredAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownInventoryEntityViolation>()),
      );
    });
  });
}
