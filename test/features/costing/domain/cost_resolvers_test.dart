import 'package:abakus_one_v2/features/costing/data/purchase_price_repository.dart';
import 'package:abakus_one_v2/features/costing/data/standard_ingredient_cost_repository.dart';
import 'package:abakus_one_v2/features/costing/domain/latest_purchase_cost_resolver.dart';
import 'package:abakus_one_v2/features/costing/domain/purchase_price.dart';
import 'package:abakus_one_v2/features/costing/domain/standard_cost_resolver.dart';
import 'package:abakus_one_v2/features/costing/domain/standard_ingredient_cost.dart';
import 'package:abakus_one_v2/features/costing/domain/weighted_average_cost_resolver.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LatestPurchaseCostResolver', () {
    test('resolves to the most recently recorded matching-unit price',
        () async {
      final repository = InMemoryPurchasePriceRepository();
      await repository.save(PurchasePrice(
        id: 'p1',
        organizationId: 'org-1',
        ingredientId: 'chicken',
        pricePerUnit: Money.fromWhole(40, Currency.tryLira),
        unit: InventoryUnit.kilogram,
        quantityPurchased: Quantity.fromWhole(5, InventoryUnit.kilogram),
        recordedAt: DateTime(2026, 1, 1),
        createdByStaffId: 'admin-1',
        createdAt: DateTime(2026, 1, 1),
      ));
      await repository.save(PurchasePrice(
        id: 'p2',
        organizationId: 'org-1',
        ingredientId: 'chicken',
        pricePerUnit: Money.fromWhole(45, Currency.tryLira),
        unit: InventoryUnit.kilogram,
        quantityPurchased: Quantity.fromWhole(3, InventoryUnit.kilogram),
        recordedAt: DateTime(2026, 1, 10),
        createdByStaffId: 'admin-1',
        createdAt: DateTime(2026, 1, 10),
      ));

      final resolver = LatestPurchaseCostResolver(repository: repository);
      final cost = await resolver.resolveUnitCost(
        ingredientId: 'chicken',
        unit: InventoryUnit.kilogram,
      );

      expect(
          cost!.minorUnits, Money.fromWhole(45, Currency.tryLira).minorUnits);
    });

    test('returns null when nothing is on record', () async {
      final resolver = LatestPurchaseCostResolver(
          repository: InMemoryPurchasePriceRepository());
      final cost = await resolver.resolveUnitCost(
        ingredientId: 'missing',
        unit: InventoryUnit.gram,
      );
      expect(cost, isNull);
    });
  });

  group('WeightedAverageCostResolver', () {
    test('weights by quantity purchased, not a naive average of prices',
        () async {
      final repository = InMemoryPurchasePriceRepository();
      // 2kg at 45.00, 1kg at 50.00 -> weighted avg = (45*2 + 50*1)/3 = 46.67
      await repository.save(PurchasePrice(
        id: 'p1',
        organizationId: 'org-1',
        ingredientId: 'chicken',
        pricePerUnit: Money.fromWhole(45, Currency.tryLira),
        unit: InventoryUnit.kilogram,
        quantityPurchased: Quantity.fromWhole(2, InventoryUnit.kilogram),
        recordedAt: DateTime(2026, 1, 1),
        createdByStaffId: 'admin-1',
        createdAt: DateTime(2026, 1, 1),
      ));
      await repository.save(PurchasePrice(
        id: 'p2',
        organizationId: 'org-1',
        ingredientId: 'chicken',
        pricePerUnit: Money.fromWhole(50, Currency.tryLira),
        unit: InventoryUnit.kilogram,
        quantityPurchased: Quantity.fromWhole(1, InventoryUnit.kilogram),
        recordedAt: DateTime(2026, 1, 10),
        createdByStaffId: 'admin-1',
        createdAt: DateTime(2026, 1, 10),
      ));

      final resolver = WeightedAverageCostResolver(repository: repository);
      final cost = await resolver.resolveUnitCost(
        ingredientId: 'chicken',
        unit: InventoryUnit.kilogram,
      );

      // 45*200 + 50*100 (kg smallestUnitsPerWhole=1000, so scale by 1000):
      // exact integer math: (4500*2000 + 5000*1000) / 3000 = 14,000,000/3000 = 4666
      expect(cost!.minorUnits, 4666);
    });
  });

  group('StandardCostResolver', () {
    test('resolves the manually-set standard cost for a matching unit',
        () async {
      final repository = InMemoryStandardIngredientCostRepository();
      await repository.save(StandardIngredientCost(
        id: 's1',
        organizationId: 'org-1',
        ingredientId: 'rice',
        unitCost: Money.fromWhole(20, Currency.tryLira),
        unit: InventoryUnit.kilogram,
        setByStaffId: 'admin-1',
        setAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final resolver = StandardCostResolver(repository: repository);
      final cost = await resolver.resolveUnitCost(
        ingredientId: 'rice',
        unit: InventoryUnit.kilogram,
      );

      expect(
          cost!.minorUnits, Money.fromWhole(20, Currency.tryLira).minorUnits);
    });

    test('returns null on a unit mismatch', () async {
      final repository = InMemoryStandardIngredientCostRepository();
      await repository.save(StandardIngredientCost(
        id: 's1',
        organizationId: 'org-1',
        ingredientId: 'rice',
        unitCost: Money.fromWhole(20, Currency.tryLira),
        unit: InventoryUnit.kilogram,
        setByStaffId: 'admin-1',
        setAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      final resolver = StandardCostResolver(repository: repository);
      final cost = await resolver.resolveUnitCost(
        ingredientId: 'rice',
        unit: InventoryUnit.gram,
      );

      expect(cost, isNull);
    });
  });
}
