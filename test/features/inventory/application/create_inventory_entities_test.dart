import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/ingredient_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/inventory_item_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/stock_location_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/identity/warehouse_id_generator.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/create_ingredient.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/create_inventory_item.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/create_stock_location.dart';
import 'package:abakus_one_v2/features/inventory/application/use_cases/create_warehouse.dart';
import 'package:abakus_one_v2/features/inventory/data/ingredient_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_item_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/stock_location_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/warehouse_repository.dart';
import 'package:abakus_one_v2/features/inventory/domain/ingredient.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_audit_event_type.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/inventory_test_fixtures.dart';

void main() {
  group('CreateIngredient', () {
    test('a manager creates a tenant-scoped ingredient', () async {
      final repository = InMemoryIngredientRepository();
      final auditRepository = InMemoryInventoryAuditEntryRepository();
      final useCase = CreateIngredient(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialIngredientIdGenerator(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final ingredient = await useCase(
        organizationId: 'org-1',
        name: 'Tavuk Göğsü',
        baseUnit: InventoryUnit.gram,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(ingredient.organizationId, 'org-1');
      expect(await repository.findById(ingredient.id), isNotNull);

      final entries = await auditRepository.findByTargetEntityId(ingredient.id);
      expect(entries.single.type, InventoryAuditEventType.ingredientCreated);
      expect(entries.single.actorId, 'manager-1');
    });

    test('an unauthorized actor is denied', () async {
      final useCase = CreateIngredient(
        authorizationPolicy: const DenyAllInventoryPolicy(),
        idGenerator: SequentialIngredientIdGenerator(),
        repository: InMemoryIngredientRepository(),
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          name: 'Tavuk Göğsü',
          baseUnit: InventoryUnit.gram,
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('CreateInventoryItem', () {
    test('begins tracking an existing ingredient', () async {
      final ingredientRepository = InMemoryIngredientRepository();
      await ingredientRepository.save(Ingredient(
        id: 'ingredient-1',
        organizationId: 'org-1',
        name: 'Tavuk Göğsü',
        baseUnit: InventoryUnit.gram,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final auditRepository = InMemoryInventoryAuditEntryRepository();
      final useCase = CreateInventoryItem(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialInventoryItemIdGenerator(),
        repository: InMemoryInventoryItemRepository(),
        ingredientRepository: ingredientRepository,
        auditRepository: auditRepository,
      );

      final item = await useCase(
        ingredientId: 'ingredient-1',
        trackingUnit: InventoryUnit.gram,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(item.organizationId, 'org-1');

      final entries = await auditRepository.findByTargetEntityId(item.id);
      expect(entries.single.type, InventoryAuditEventType.inventoryItemCreated);
    });

    test('an unknown ingredient throws', () async {
      final useCase = CreateInventoryItem(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialInventoryItemIdGenerator(),
        repository: InMemoryInventoryItemRepository(),
        ingredientRepository: InMemoryIngredientRepository(),
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      expect(
        () => useCase(
          ingredientId: 'missing',
          trackingUnit: InventoryUnit.gram,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownInventoryEntityViolation>()),
      );
    });

    test('an unauthorized actor is denied', () async {
      final useCase = CreateInventoryItem(
        authorizationPolicy: const DenyAllInventoryPolicy(),
        idGenerator: SequentialInventoryItemIdGenerator(),
        repository: InMemoryInventoryItemRepository(),
        ingredientRepository: InMemoryIngredientRepository(),
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      expect(
        () => useCase(
          ingredientId: 'ingredient-1',
          trackingUnit: InventoryUnit.gram,
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('CreateStockLocation', () {
    test('a manager creates a branch-scoped location', () async {
      final auditRepository = InMemoryInventoryAuditEntryRepository();
      final useCase = CreateStockLocation(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialStockLocationIdGenerator(),
        repository: InMemoryStockLocationRepository(),
        auditRepository: auditRepository,
      );

      final location = await useCase(
        branchId: 'branch-1',
        name: 'Ana Depo',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(location.branchId, 'branch-1');

      final entries = await auditRepository.findByTargetEntityId(location.id);
      expect(entries.single.type, InventoryAuditEventType.stockLocationCreated);
      expect(entries.single.branchId, 'branch-1');
    });

    test('an unauthorized actor is denied', () async {
      final useCase = CreateStockLocation(
        authorizationPolicy: const DenyAllInventoryPolicy(),
        idGenerator: SequentialStockLocationIdGenerator(),
        repository: InMemoryStockLocationRepository(),
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      expect(
        () => useCase(
          branchId: 'branch-1',
          name: 'Ana Depo',
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('CreateWarehouse', () {
    test('a manager creates a restaurant-scoped warehouse', () async {
      final auditRepository = InMemoryInventoryAuditEntryRepository();
      final useCase = CreateWarehouse(
        authorizationPolicy: const AllowAllInventoryPolicy(),
        idGenerator: SequentialWarehouseIdGenerator(),
        repository: InMemoryWarehouseRepository(),
        auditRepository: auditRepository,
      );

      final warehouse = await useCase(
        restaurantId: 'restaurant-1',
        name: 'Merkez Depo',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(warehouse.restaurantId, 'restaurant-1');

      final entries = await auditRepository.findByTargetEntityId(warehouse.id);
      expect(entries.single.type, InventoryAuditEventType.warehouseCreated);
      expect(entries.single.branchId, isNull);
    });

    test('an unauthorized actor is denied', () async {
      final useCase = CreateWarehouse(
        authorizationPolicy: const DenyAllInventoryPolicy(),
        idGenerator: SequentialWarehouseIdGenerator(),
        repository: InMemoryWarehouseRepository(),
        auditRepository: InMemoryInventoryAuditEntryRepository(),
      );

      expect(
        () => useCase(
          restaurantId: 'restaurant-1',
          name: 'Merkez Depo',
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
