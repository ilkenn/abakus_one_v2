import 'package:abakus_one_v2/features/inventory/domain/branch_stock.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_item.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/negative_stock_policy.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/inventory/domain/stock_health_status.dart';
import 'package:flutter_test/flutter_test.dart';

InventoryItem _buildItem({
  Quantity? reorderThreshold,
  NegativeStockPolicy negativeStockPolicy = NegativeStockPolicy.forbid,
}) {
  return InventoryItem(
    id: 'item-1',
    ingredientId: 'ingredient-1',
    organizationId: 'org-1',
    trackingUnit: InventoryUnit.gram,
    reorderThreshold: reorderThreshold,
    negativeStockPolicy: negativeStockPolicy,
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

BranchStock _buildStock(int smallestUnits, {bool isNegativeStockWarning = false}) {
  return BranchStock(
    inventoryItemId: 'item-1',
    locationId: 'branch-1',
    branchId: 'branch-1',
    quantityOnHand: Quantity(smallestUnits, InventoryUnit.gram),
    isNegativeStockWarning: isNegativeStockWarning,
    lastMovementId: 'move-1',
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('StockHealthStatusResolver.compute', () {
    test('no BranchStock record at all -> healthy (nothing tracked yet)', () {
      final status = StockHealthStatusResolver.compute(
        item: _buildItem(reorderThreshold: Quantity.fromWhole(500, InventoryUnit.gram)),
        branchStock: null,
      );
      expect(status, StockHealthStatus.healthy);
    });

    test('on-hand above the reorder threshold -> healthy', () {
      final status = StockHealthStatusResolver.compute(
        item: _buildItem(reorderThreshold: Quantity.fromWhole(500, InventoryUnit.gram)),
        branchStock: _buildStock(1000),
      );
      expect(status, StockHealthStatus.healthy);
    });

    test('on-hand exactly at the reorder threshold -> lowStock', () {
      final status = StockHealthStatusResolver.compute(
        item: _buildItem(reorderThreshold: Quantity.fromWhole(500, InventoryUnit.gram)),
        branchStock: _buildStock(500),
      );
      expect(status, StockHealthStatus.lowStock);
    });

    test('on-hand below the reorder threshold -> lowStock', () {
      final status = StockHealthStatusResolver.compute(
        item: _buildItem(reorderThreshold: Quantity.fromWhole(500, InventoryUnit.gram)),
        branchStock: _buildStock(100),
      );
      expect(status, StockHealthStatus.lowStock);
    });

    test('no reorderThreshold configured -> never lowStock, regardless of quantity', () {
      final status = StockHealthStatusResolver.compute(
        item: _buildItem(),
        branchStock: _buildStock(1),
      );
      expect(status, StockHealthStatus.healthy);
    });

    test('on-hand exactly zero -> outOfStock, even with a configured threshold', () {
      final status = StockHealthStatusResolver.compute(
        item: _buildItem(reorderThreshold: Quantity.fromWhole(500, InventoryUnit.gram)),
        branchStock: _buildStock(0),
      );
      expect(status, StockHealthStatus.outOfStock);
    });

    test(
        'negative on-hand (allowed under warn/allow policy) -> outOfStock, never lowStock',
        () {
      final status = StockHealthStatusResolver.compute(
        item: _buildItem(
          reorderThreshold: Quantity.fromWhole(500, InventoryUnit.gram),
          negativeStockPolicy: NegativeStockPolicy.warn,
        ),
        branchStock: _buildStock(-50, isNegativeStockWarning: true),
      );
      expect(status, StockHealthStatus.outOfStock);
    });
  });
}
