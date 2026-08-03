import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/stock_count_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/stock_count_line_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/stock_movement_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/add_stock_count_line.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/approve_stock_count.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/record_stock_movement.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/start_stock_count.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/submit_stock_count.dart';
import 'package:abakus_one_v2/features/inventory/data/branch_stock_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_item_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/stock_count_line_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/stock_count_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/stock_movement_repository.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_item.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/negative_stock_policy.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/inventory/domain/stock_count.dart';
import 'package:abakus_one_v2/features/inventory/domain/stock_movement_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/inventory_test_fixtures.dart';

void main() {
  group('StockCount workflow', () {
    test(
        'start -> add lines -> submit -> approve applies count '
        'corrections for non-zero variance lines only', () async {
      final inventoryItemRepository = InMemoryInventoryItemRepository();
      await inventoryItemRepository.save(InventoryItem(
        id: 'item-rice',
        ingredientId: 'ingredient-rice',
        organizationId: 'org-1',
        trackingUnit: InventoryUnit.gram,
        negativeStockPolicy: NegativeStockPolicy.allow,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      await inventoryItemRepository.save(InventoryItem(
        id: 'item-chicken',
        ingredientId: 'ingredient-chicken',
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

      // Seed 1000g rice on hand, 500g chicken on hand.
      await recordStockMovement(
        branchId: 'branch-1',
        inventoryItemId: 'item-rice',
        locationId: 'location-1',
        type: StockMovementType.receipt,
        quantityDelta: Quantity.fromWhole(1000, InventoryUnit.gram),
        idempotencyKey: 'seed-rice',
        performedByStaffId: 'manager-1',
        occurredAt: DateTime(2026, 1, 1),
      );
      await recordStockMovement(
        branchId: 'branch-1',
        inventoryItemId: 'item-chicken',
        locationId: 'location-1',
        type: StockMovementType.receipt,
        quantityDelta: Quantity.fromWhole(500, InventoryUnit.gram),
        idempotencyKey: 'seed-chicken',
        performedByStaffId: 'manager-1',
        occurredAt: DateTime(2026, 1, 1),
      );

      final countRepository = InMemoryStockCountRepository();
      final count = await StartStockCount(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialStockCountIdGenerator(),
        repository: countRepository,
      )(
        branchId: 'branch-1',
        locationId: 'location-1',
        performedByStaffId: 'staff-1',
        performedAt: DateTime(2026, 1, 2),
      );

      final lineRepository = InMemoryStockCountLineRepository();
      final addLine = AddStockCountLine(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialStockCountLineIdGenerator(),
        countRepository: countRepository,
        lineRepository: lineRepository,
        branchStockRepository: branchStockRepository,
      );
      // Rice: counted 950g (50g short, real variance).
      await addLine(
        countId: count.id,
        inventoryItemId: 'item-rice',
        locationId: 'location-1',
        countedQuantity: Quantity.fromWhole(950, InventoryUnit.gram),
        performedByStaffId: 'staff-1',
      );
      // Chicken: counted exactly 500g (no variance).
      await addLine(
        countId: count.id,
        inventoryItemId: 'item-chicken',
        locationId: 'location-1',
        countedQuantity: Quantity.fromWhole(500, InventoryUnit.gram),
        performedByStaffId: 'staff-1',
      );

      await SubmitStockCount(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        repository: countRepository,
      )(
        countId: count.id,
        performedByStaffId: 'staff-1',
        performedAt: DateTime(2026, 1, 2),
      );

      final approve = ApproveStockCount(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        repository: countRepository,
        lineRepository: lineRepository,
        recordStockMovement: recordStockMovement,
      );
      final approved = await approve(
        approve: true,
        countId: count.id,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 3),
      );

      expect(approved.status, StockCountStatus.approved);

      final riceBalance = await branchStockRepository.findByItemAndLocation(
          'item-rice', 'location-1');
      expect(riceBalance!.quantityOnHand.smallestUnits, 950);

      final chickenBalance = await branchStockRepository.findByItemAndLocation(
          'item-chicken', 'location-1');
      // Unchanged: no movement should have been recorded for a zero
      // variance line.
      expect(chickenBalance!.quantityOnHand.smallestUnits, 500);
    });

    test('the staff member who started the count cannot approve it', () async {
      final countRepository = InMemoryStockCountRepository();
      final count = await StartStockCount(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialStockCountIdGenerator(),
        repository: countRepository,
      )(
        branchId: 'branch-1',
        locationId: 'location-1',
        performedByStaffId: 'staff-1',
        performedAt: DateTime(2026, 1, 2),
      );
      await SubmitStockCount(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        repository: countRepository,
      )(
        countId: count.id,
        performedByStaffId: 'staff-1',
        performedAt: DateTime(2026, 1, 2),
      );

      final approve = ApproveStockCount(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        repository: countRepository,
        lineRepository: InMemoryStockCountLineRepository(),
        recordStockMovement: RecordStockMovement(
          idGenerator: SequentialStockMovementIdGenerator(),
          movementRepository: InMemoryStockMovementRepository(),
          branchStockRepository: InMemoryBranchStockRepository(),
          inventoryItemRepository: InMemoryInventoryItemRepository(),
          auditRepository: InMemoryInventoryAuditEntryRepository(),
        ),
      );

      expect(
        () => approve(
          approve: true,
          countId: count.id,
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 3),
        ),
        throwsA(isA<SelfApprovalNotAllowedViolation>()),
      );
    });

    test('rejecting a count never touches stock', () async {
      final countRepository = InMemoryStockCountRepository();
      final count = await StartStockCount(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialStockCountIdGenerator(),
        repository: countRepository,
      )(
        branchId: 'branch-1',
        locationId: 'location-1',
        performedByStaffId: 'staff-1',
        performedAt: DateTime(2026, 1, 2),
      );
      await SubmitStockCount(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        repository: countRepository,
      )(
        countId: count.id,
        performedByStaffId: 'staff-1',
        performedAt: DateTime(2026, 1, 2),
      );

      final branchStockRepository = InMemoryBranchStockRepository();
      final rejected = await ApproveStockCount(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        repository: countRepository,
        lineRepository: InMemoryStockCountLineRepository(),
        recordStockMovement: RecordStockMovement(
          idGenerator: SequentialStockMovementIdGenerator(),
          movementRepository: InMemoryStockMovementRepository(),
          branchStockRepository: branchStockRepository,
          inventoryItemRepository: InMemoryInventoryItemRepository(),
          auditRepository: InMemoryInventoryAuditEntryRepository(),
        ),
      )(
        approve: false,
        countId: count.id,
        rejectionReason: 'Sayım hatalı yapılmış, tekrar edilecek',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 3),
      );

      expect(rejected.status, StockCountStatus.rejected);
      expect(
        await branchStockRepository.findByItemAndLocation(
            'item-rice', 'location-1'),
        isNull,
      );
    });
  });
}
