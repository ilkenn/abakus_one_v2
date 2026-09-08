import 'package:abakus_one_v2/features/menu/data/menu_product_repository.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_ingredient_link_gateway.dart';
import 'package:abakus_one_v2/features/recipes/data/recipe_ingredient_link_repository.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_ingredient_link.dart';
import 'package:abakus_one_v2/features/recipes/presentation/providers/recipe_dependencies_provider.dart';
import 'package:abakus_one_v2/features/recipes/presentation/screens/recipe_ingredient_links_screen.dart';
import 'package:abakus_one_v2/features/smart_import/presentation/providers/smart_import_dependencies_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRecipeIngredientLinkGateway implements RecipeIngredientLinkGateway {
  String? lastProductId;
  String? lastRecipeVersionId;
  List<RecipeIngredientLinkLineInput>? lastIngredients;
  int callCount = 0;

  @override
  Future<SetRecipeIngredientLinkResult> setLink({
    required String organizationId,
    required String productId,
    required String recipeVersionId,
    required List<RecipeIngredientLinkLineInput> ingredients,
  }) async {
    callCount += 1;
    lastProductId = productId;
    lastRecipeVersionId = recipeVersionId;
    lastIngredients = ingredients;
    return const SetRecipeIngredientLinkResult(linkId: 'link-1', revision: 1);
  }
}

MenuProduct _buildProduct(String id, String name) {
  return MenuProduct(
    id: id,
    categoryId: 'cat-1',
    name: name,
    description: '',
    basePrice: 100,
    imageKey: 'bowl',
  );
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<MenuProduct> products,
    RecipeIngredientLink? existingLink,
    RecipeIngredientLinkGateway? gateway,
  }) async {
    final productRepository = InMemoryMenuProductRepository(seed: products);
    final linkRepository = InMemoryRecipeIngredientLinkRepository();
    if (existingLink != null) await linkRepository.save(existingLink);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          menuProductRepositoryProvider.overrideWithValue(productRepository),
          recipeIngredientLinkRepositoryProvider
              .overrideWithValue(linkRepository),
          if (gateway != null)
            recipeIngredientLinkGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(
          home: RecipeIngredientLinksScreen(organizationId: 'org-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists products with their link status', (tester) async {
    await pumpScreen(
      tester,
      products: [_buildProduct('p1', 'Mexifit Bowl')],
    );

    expect(find.text('Mexifit Bowl'), findsOneWidget);
    expect(find.text('Bağlantı yok'), findsOneWidget);
  });

  testWidgets('a linked product shows its ingredient count', (tester) async {
    await pumpScreen(
      tester,
      products: [_buildProduct('p1', 'Mexifit Bowl')],
      existingLink: RecipeIngredientLink(
        id: 'link-1',
        organizationId: 'org-1',
        productId: 'p1',
        recipeVersionId: 'rv-1',
        ingredients: const [],
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ),
    );

    expect(find.text('0 malzeme bağlı'), findsOneWidget);
  });

  testWidgets(
      'tapping a product opens the form and saving calls the gateway with the entered ingredient line',
      (tester) async {
    final gateway = _FakeRecipeIngredientLinkGateway();
    await pumpScreen(
      tester,
      products: [_buildProduct('p1', 'Mexifit Bowl')],
      gateway: gateway,
    );

    await tester.tap(find.text('Mexifit Bowl'));
    await tester.pumpAndSettle();

    expect(find.text('Malzemeler'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Reçete Versiyon Kimliği'), 'rv-1');
    await tester.enterText(
        find.widgetWithText(TextField, 'Malzeme Kimliği (Inventory Item ID)'),
        'item-chicken');
    await tester.enterText(find.widgetWithText(TextField, 'Miktar'), '150');

    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(gateway.callCount, 1);
    expect(gateway.lastProductId, 'p1');
    expect(gateway.lastRecipeVersionId, 'rv-1');
    expect(gateway.lastIngredients, hasLength(1));
    expect(gateway.lastIngredients!.single.inventoryItemId, 'item-chicken');
    expect(gateway.lastIngredients!.single.quantitySmallestUnits, 150);
    expect(gateway.lastIngredients!.single.unitCode, 'g');

    // Saving pops back to the list, which reloads and shows the new link.
    expect(find.text('1 malzeme bağlı'), findsOneWidget);
  });

  testWidgets('an empty inventory item id is rejected before calling the gateway',
      (tester) async {
    final gateway = _FakeRecipeIngredientLinkGateway();
    await pumpScreen(
      tester,
      products: [_buildProduct('p1', 'Mexifit Bowl')],
      gateway: gateway,
    );

    await tester.tap(find.text('Mexifit Bowl'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Reçete Versiyon Kimliği'), 'rv-1');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(gateway.callCount, 0);
    expect(find.textContaining('geçerli bir malzeme kimliği'), findsOneWidget);
  });
}
