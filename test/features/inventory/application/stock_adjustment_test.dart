import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/stock_adjustment_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/stock_movement_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/approve_stock_adjustment.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/record_stock_movement.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/request_stock_adjustment.dart';
import 'package:abakus_one_v2/features/inventory/data/branch_stock_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_item_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/stock_adjustment_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/stock_movement_repository.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_item.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/negative_stock_policy.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/inventory/domain/stock_adjustment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/inventory_test_fixtures.dart';

void main() {
  group('RequestStockAdjustment', () {
    test('requires a non-empty reason', () async {
      final useCase = RequestStockAdjustment(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialStockAdjustmentIdGenerator(),
        repository: InMemoryStockAdjustmentRepository(),
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      expect(
        () => useCase(
          branchId: 'branch-1',
          inventoryItemId: 'item-1',
          locationId: 'location-1',
          quantityDelta: Quantity.fromWhole(-10, InventoryUnit.gram),
          reason: '   ',
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<InventoryReasonRequiredViolation>()),
      );
    });
  });

  group('ApproveStockAdjustment', () {
    test('the requester cannot approve their own adjustment', () async {
      final adjustmentRepository = InMemoryStockAdjustmentRepository();
      await adjustmentRepository.save(StockAdjustment(
        id: 'adj-1',
        branchId: 'branch-1',
        inventoryItemId: 'item-1',
        locationId: 'location-1',
        quantityDelta: Quantity.fromWhole(-10, InventoryUnit.gram),
        reason: 'Sayım farkı',
        requestedByStaffId: 'staff-1',
        createdAt: DateTime(2026, 1, 1),
      ));
      final itemRepository = InMemoryInventoryItemRepository();
      await itemRepository.save(InventoryItem(
        id: 'item-1',
        ingredientId: 'ingredient-1',
        organizationId: 'org-1',
        trackingUnit: InventoryUnit.gram,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final useCase = ApproveStockAdjustment(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        repository: adjustmentRepository,
        recordStockMovement: RecordStockMovement(
          idGenerator: SequentialStockMovementIdGenerator(),
          movementRepository: InMemoryStockMovementRepository(),
          branchStockRepository: InMemoryBranchStockRepository(),
          inventoryItemRepository: itemRepository,
          auditRepository: InMemoryInventoryAuditEntryRepository(),
        ),
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      expect(
        () => useCase(
          adjustmentId: 'adj-1',
          approve: true,
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 2),
        ),
        throwsA(isA<SelfApprovalNotAllowedViolation>()),
      );
    });

    test('a different manager can approve, producing a real StockMovement',
        () async {
      final adjustmentRepository = InMemoryStockAdjustmentRepository();
      await adjustmentRepository.save(StockAdjustment(
        id: 'adj-1',
        branchId: 'branch-1',
        inventoryItemId: 'item-1',
        locationId: 'location-1',
        quantityDelta: Quantity.fromWhole(-10, InventoryUnit.gram),
        reason: 'Sayım farkı',
        requestedByStaffId: 'staff-1',
        createdAt: DateTime(2026, 1, 1),
      ));
      final itemRepository = InMemoryInventoryItemRepository();
      await itemRepository.save(InventoryItem(
        id: 'item-1',
        ingredientId: 'ingredient-1',
        organizationId: 'org-1',
        trackingUnit: InventoryUnit.gram,
        negativeStockPolicy: NegativeStockPolicy.allow,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final branchStockRepository = InMemoryBranchStockRepository();
      final useCase = ApproveStockAdjustment(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        repository: adjustmentRepository,
        recordStockMovement: RecordStockMovement(
          idGenerator: SequentialStockMovementIdGenerator(),
          movementRepository: InMemoryStockMovementRepository(),
          branchStockRepository: branchStockRepository,
          inventoryItemRepository: itemRepository,
          auditRepository: InMemoryInventoryAuditEntryRepository(),
        ),
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      final result = await useCase(
        adjustmentId: 'adj-1',
        approve: true,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(result.status, StockAdjustmentStatus.approved);
      final balance = await branchStockRepository.findByItemAndLocation(
          'item-1', 'location-1');
      expect(balance!.quantityOnHand.smallestUnits, -10);
    });

    test('rejecting never touches stock', () async {
      final adjustmentRepository = InMemoryStockAdjustmentRepository();
      await adjustmentRepository.save(StockAdjustment(
        id: 'adj-1',
        branchId: 'branch-1',
        inventoryItemId: 'item-1',
        locationId: 'location-1',
        quantityDelta: Quantity.fromWhole(-10, InventoryUnit.gram),
        reason: 'Sayım farkı',
        requestedByStaffId: 'staff-1',
        createdAt: DateTime(2026, 1, 1),
      ));
      final branchStockRepository = InMemoryBranchStockRepository();
      final useCase = ApproveStockAdjustment(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        repository: adjustmentRepository,
        recordStockMovement: RecordStockMovement(
          idGenerator: SequentialStockMovementIdGenerator(),
          movementRepository: InMemoryStockMovementRepository(),
          branchStockRepository: branchStockRepository,
          inventoryItemRepository: InMemoryInventoryItemRepository(),
          auditRepository: InMemoryInventoryAuditEntryRepository(),
        ),
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      final result = await useCase(
        adjustmentId: 'adj-1',
        approve: false,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(result.status, StockAdjustmentStatus.rejected);
      expect(
        await branchStockRepository.findByItemAndLocation(
            'item-1', 'location-1'),
        isNull,
      );
    });

    test('an already-decided adjustment cannot be re-approved', () async {
      final adjustmentRepository = InMemoryStockAdjustmentRepository();
      await adjustmentRepository.save(StockAdjustment(
        id: 'adj-1',
        branchId: 'branch-1',
        inventoryItemId: 'item-1',
        locationId: 'location-1',
        quantityDelta: Quantity.fromWhole(-10, InventoryUnit.gram),
        reason: 'Sayım farkı',
        requestedByStaffId: 'staff-1',
        status: StockAdjustmentStatus.approved,
        createdAt: DateTime(2026, 1, 1),
      ));
      final useCase = ApproveStockAdjustment(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        repository: adjustmentRepository,
        recordStockMovement: RecordStockMovement(
          idGenerator: SequentialStockMovementIdGenerator(),
          movementRepository: InMemoryStockMovementRepository(),
          branchStockRepository: InMemoryBranchStockRepository(),
          inventoryItemRepository: InMemoryInventoryItemRepository(),
          auditRepository: InMemoryInventoryAuditEntryRepository(),
        ),
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      expect(
        () => useCase(
          adjustmentId: 'adj-1',
          approve: true,
          performedByStaffId: 'manager-2',
          performedAt: DateTime(2026, 1, 2),
        ),
        throwsA(isA<InvalidInventoryWorkflowTransitionViolation>()),
      );
    });
  });
}
