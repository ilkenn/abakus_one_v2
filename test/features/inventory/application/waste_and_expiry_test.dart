import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/expiry_record_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/stock_movement_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/waste_record_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/dispose_expired_lot.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/get_expiry_warnings.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/record_stock_movement.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/record_waste.dart';
import 'package:abakus_one_v2/features/inventory/data/branch_stock_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/expiry_record_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_item_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/stock_lot_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/stock_movement_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/waste_record_repository.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_item.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/negative_stock_policy.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/inventory/domain/stock_lot.dart';
import 'package:abakus_one_v2/features/inventory/domain/stock_movement_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/inventory_test_fixtures.dart';

InventoryItem _buildItem(
    {NegativeStockPolicy policy = NegativeStockPolicy.allow}) {
  return InventoryItem(
    id: 'item-rice',
    ingredientId: 'ingredient-rice',
    organizationId: 'org-1',
    trackingUnit: InventoryUnit.gram,
    negativeStockPolicy: policy,
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

void main() {
  group('RecordWaste', () {
    test('reduces on-hand quantity via a real, negative StockMovement',
        () async {
      final inventoryItemRepository = InMemoryInventoryItemRepository();
      await inventoryItemRepository.save(_buildItem());
      final branchStockRepository = InMemoryBranchStockRepository();
      final recordStockMovement = RecordStockMovement(
        idGenerator: SequentialStockMovementIdGenerator(),
        movementRepository: InMemoryStockMovementRepository(),
        branchStockRepository: branchStockRepository,
        inventoryItemRepository: inventoryItemRepository,
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );
      await recordStockMovement(
        branchId: 'branch-1',
        inventoryItemId: 'item-rice',
        locationId: 'location-1',
        type: StockMovementType.receipt,
        quantityDelta: Quantity.fromWhole(1000, InventoryUnit.gram),
        idempotencyKey: 'seed',
        performedByStaffId: 'manager-1',
        occurredAt: DateTime(2026, 1, 1),
      );

      final useCase = RecordWaste(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialWasteRecordIdGenerator(),
        repository: InMemoryWasteRecordRepository(),
        recordStockMovement: recordStockMovement,
      );

      final record = await useCase(
        branchId: 'branch-1',
        inventoryItemId: 'item-rice',
        locationId: 'location-1',
        quantity: Quantity.fromWhole(200, InventoryUnit.gram),
        reason: 'Düşürüldü',
        performedByStaffId: 'staff-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(record.quantity.smallestUnits, 200,
          reason: 'WasteRecord.quantity is always the positive wasted amount');
      final balance = await branchStockRepository.findByItemAndLocation(
          'item-rice', 'location-1');
      expect(balance!.quantityOnHand.smallestUnits, 800);
    });

    test('an empty reason throws', () async {
      final useCase = RecordWaste(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialWasteRecordIdGenerator(),
        repository: InMemoryWasteRecordRepository(),
        recordStockMovement: RecordStockMovement(
          idGenerator: SequentialStockMovementIdGenerator(),
          movementRepository: InMemoryStockMovementRepository(),
          branchStockRepository: InMemoryBranchStockRepository(),
          inventoryItemRepository: InMemoryInventoryItemRepository(),
          auditRepository: InMemoryInventoryAuditEntryRepository(),
        ),
      );

      expect(
        () => useCase(
          branchId: 'branch-1',
          inventoryItemId: 'item-rice',
          locationId: 'location-1',
          quantity: Quantity.fromWhole(1, InventoryUnit.gram),
          reason: '   ',
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<InventoryReasonRequiredViolation>()),
      );
    });
  });

  group('DisposeExpiredLot', () {
    test(
        'reduces stock by the lot\'s remaining quantity and records an '
        'ExpiryRecord', () async {
      final inventoryItemRepository = InMemoryInventoryItemRepository();
      await inventoryItemRepository.save(_buildItem());
      final branchStockRepository = InMemoryBranchStockRepository();
      final recordStockMovement = RecordStockMovement(
        idGenerator: SequentialStockMovementIdGenerator(),
        movementRepository: InMemoryStockMovementRepository(),
        branchStockRepository: branchStockRepository,
        inventoryItemRepository: inventoryItemRepository,
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );
      await recordStockMovement(
        branchId: 'branch-1',
        inventoryItemId: 'item-rice',
        locationId: 'location-1',
        type: StockMovementType.receipt,
        quantityDelta: Quantity.fromWhole(500, InventoryUnit.gram),
        idempotencyKey: 'seed',
        performedByStaffId: 'manager-1',
        occurredAt: DateTime(2026, 1, 1),
      );

      final lotRepository = InMemoryStockLotRepository();
      await lotRepository.save(StockLot(
        id: 'lot-1',
        inventoryItemId: 'item-rice',
        locationId: 'location-1',
        quantityReceived: Quantity.fromWhole(500, InventoryUnit.gram),
        quantityRemaining: Quantity.fromWhole(500, InventoryUnit.gram),
        receivedAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2026, 1, 3),
      ));

      final expiryRepository = InMemoryExpiryRecordRepository();
      final useCase = DisposeExpiredLot(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialExpiryRecordIdGenerator(),
        lotRepository: lotRepository,
        repository: expiryRepository,
        recordStockMovement: recordStockMovement,
      );

      final record = await useCase(
        branchId: 'branch-1',
        lotId: 'lot-1',
        performedByStaffId: 'staff-1',
        performedAt: DateTime(2026, 1, 4),
      );

      expect(record.disposedQuantity.smallestUnits, 500);
      final balance = await branchStockRepository.findByItemAndLocation(
          'item-rice', 'location-1');
      expect(balance!.quantityOnHand.smallestUnits, 0);
    });
  });

  group('GetExpiryWarnings', () {
    test('only returns lots expiring within the given window', () async {
      final lotRepository = InMemoryStockLotRepository();
      await lotRepository.save(StockLot(
        id: 'lot-soon',
        inventoryItemId: 'item-rice',
        locationId: 'location-1',
        quantityReceived: Quantity.fromWhole(100, InventoryUnit.gram),
        quantityRemaining: Quantity.fromWhole(100, InventoryUnit.gram),
        receivedAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2026, 1, 5),
      ));
      await lotRepository.save(StockLot(
        id: 'lot-later',
        inventoryItemId: 'item-rice',
        locationId: 'location-1',
        quantityReceived: Quantity.fromWhole(100, InventoryUnit.gram),
        quantityRemaining: Quantity.fromWhole(100, InventoryUnit.gram),
        receivedAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2026, 2, 20),
      ));

      final useCase = GetExpiryWarnings(repository: lotRepository);
      final warnings = await useCase(
        locationId: 'location-1',
        asOf: DateTime(2026, 1, 1),
        withinDuration: const Duration(days: 7),
      );

      expect(warnings.map((l) => l.id), ['lot-soon']);
    });
  });
}
