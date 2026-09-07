import 'package:abakus_one_v2/features/inventory/data/branch_stock_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/ingredient_repository.dart';
import 'package:abakus_one_v2/features/inventory/data/inventory_item_repository.dart';
import 'package:abakus_one_v2/features/inventory/domain/branch_stock.dart';
import 'package:abakus_one_v2/features/inventory/domain/ingredient.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_item.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/inventory/presentation/providers/inventory_dependencies_provider.dart';
import 'package:abakus_one_v2/features/inventory/presentation/screens/inventory_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// AP-5 Sprint 5 — the manager inventory list's new status filter tabs and
/// [StockHealthStatus] badge.
void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<InventoryItem> items,
    required List<Ingredient> ingredients,
    required List<BranchStock> stock,
  }) async {
    final itemRepository = InMemoryInventoryItemRepository();
    for (final item in items) {
      await itemRepository.save(item);
    }
    final ingredientRepository = InMemoryIngredientRepository();
    for (final ingredient in ingredients) {
      await ingredientRepository.save(ingredient);
    }
    final stockRepository = InMemoryBranchStockRepository();
    for (final balance in stock) {
      await stockRepository.save(balance);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryItemRepositoryProvider.overrideWithValue(itemRepository),
          ingredientRepositoryProvider.overrideWithValue(ingredientRepository),
          branchStockRepositoryProvider.overrideWithValue(stockRepository),
        ],
        child: const MaterialApp(
          home: InventoryScreen(organizationId: 'org-1', branchId: 'branch-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  InventoryItem buildItem(String id, {Quantity? reorderThreshold}) {
    return InventoryItem(
      id: id,
      ingredientId: 'ingredient-$id',
      organizationId: 'org-1',
      trackingUnit: InventoryUnit.gram,
      reorderThreshold: reorderThreshold,
      createdAt: DateTime(2026, 1, 1),
      revision: 1,
    );
  }

  Ingredient buildIngredient(String id, String name) {
    return Ingredient(
      id: 'ingredient-$id',
      organizationId: 'org-1',
      name: name,
      baseUnit: InventoryUnit.gram,
      createdAt: DateTime(2026, 1, 1),
      revision: 1,
    );
  }

  BranchStock buildStock(String itemId, int smallestUnits) {
    return BranchStock(
      inventoryItemId: itemId,
      locationId: 'branch-1',
      branchId: 'branch-1',
      quantityOnHand: Quantity(smallestUnits, InventoryUnit.gram),
      lastMovementId: 'move-1',
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  testWidgets('the status filter tabs are present', (tester) async {
    await pumpScreen(tester, items: [], ingredients: [], stock: []);

    expect(find.widgetWithText(ChoiceChip, 'Tümü'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Düşük Stok'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Tükendi'), findsOneWidget);
  });

  testWidgets(
      'a healthy item shows no badge, an out-of-stock item shows the Tükendi badge',
      (tester) async {
    await pumpScreen(
      tester,
      items: [
        buildItem('healthy', reorderThreshold: Quantity.fromWhole(100, InventoryUnit.gram)),
        buildItem('depleted', reorderThreshold: Quantity.fromWhole(100, InventoryUnit.gram)),
      ],
      ingredients: [
        buildIngredient('healthy', 'Sağlıklı Malzeme'),
        buildIngredient('depleted', 'Tükenen Malzeme'),
      ],
      stock: [
        buildStock('healthy', 1000),
        buildStock('depleted', 0),
      ],
    );

    expect(find.text('Sağlıklı Malzeme'), findsOneWidget);
    expect(find.text('Tükenen Malzeme'), findsOneWidget);
    // The filter tab's own 'Tükendi' chip plus the depleted item's badge.
    expect(find.text('Tükendi'), findsNWidgets(2));
    // The filter tab's own 'Düşük Stok' chip only — no badge, since
    // nothing here is in that state.
    expect(find.text('Düşük Stok'), findsOneWidget);
  });

  testWidgets(
      'selecting the Tükendi tab hides items that are not out of stock',
      (tester) async {
    await pumpScreen(
      tester,
      items: [buildItem('healthy')],
      ingredients: [buildIngredient('healthy', 'Sağlıklı Malzeme')],
      stock: [buildStock('healthy', 1000)],
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Tükendi'));
    await tester.pumpAndSettle();

    expect(find.text('Sağlıklı Malzeme'), findsNothing);
    expect(find.text('Bu filtreyle eşleşen envanter kalemi yok.'), findsOneWidget);
  });
}
