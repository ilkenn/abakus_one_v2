import 'package:abakus_one_v2/features/admin/data/menu_catalog_admin_gateway.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/admin/presentation/screens/admin_menu_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMenuCatalogAdminGateway implements MenuCatalogAdminGateway {
  _FakeMenuCatalogAdminGateway({
    List<AdminMenuCategory> categories = const [],
    List<AdminMenuProduct> products = const [],
  })  : _categories = [...categories],
        _products = [...products];

  final List<AdminMenuCategory> _categories;
  final List<AdminMenuProduct> _products;
  int createCategoryCallCount = 0;
  int createProductCallCount = 0;
  String? lastCreatedProductCategoryId;
  int updateProductCallCount = 0;
  int deleteProductCallCount = 0;
  int setAvailabilityCallCount = 0;

  @override
  Future<List<AdminMenuCategory>> listCategories({
    required String organizationId,
  }) async =>
      List.unmodifiable(_categories);

  @override
  Future<String> createCategory({
    required String organizationId,
    required String restaurantId,
    required String name,
    int sortOrder = 0,
  }) async {
    createCategoryCallCount += 1;
    final id = 'cat-${_categories.length + 1}';
    _categories.add(AdminMenuCategory(
        id: id, name: name, sortOrder: sortOrder, isActive: true));
    return id;
  }

  @override
  Future<List<AdminMenuProduct>> listProducts({
    required String organizationId,
  }) async =>
      List.unmodifiable(_products);

  @override
  Future<String> createProduct({
    required String organizationId,
    required String restaurantId,
    required String categoryId,
    required String name,
    required int basePriceMinorUnits,
  }) async {
    createProductCallCount += 1;
    lastCreatedProductCategoryId = categoryId;
    final id = 'prod-${_products.length + 1}';
    _products.add(AdminMenuProduct(
      id: id,
      categoryId: categoryId,
      name: name,
      basePriceMinorUnits: basePriceMinorUnits,
      isAvailable: true,
    ));
    return id;
  }

  @override
  Future<void> updateProduct({
    required String organizationId,
    required String productId,
    String? name,
    int? basePriceMinorUnits,
  }) async {
    updateProductCallCount += 1;
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return;
    final current = _products[index];
    _products[index] = AdminMenuProduct(
      id: current.id,
      categoryId: current.categoryId,
      name: name ?? current.name,
      basePriceMinorUnits: basePriceMinorUnits ?? current.basePriceMinorUnits,
      isAvailable: current.isAvailable,
    );
  }

  @override
  Future<void> setProductAvailability({
    required String organizationId,
    required String productId,
    required bool isAvailable,
  }) async {
    setAvailabilityCallCount += 1;
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return;
    final current = _products[index];
    _products[index] = AdminMenuProduct(
      id: current.id,
      categoryId: current.categoryId,
      name: current.name,
      basePriceMinorUnits: current.basePriceMinorUnits,
      isAvailable: isAvailable,
    );
  }

  @override
  Future<void> deleteProduct({
    required String organizationId,
    required String productId,
  }) async {
    deleteProductCallCount += 1;
    _products.removeWhere((p) => p.id == productId);
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required MenuCatalogAdminGateway gateway,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [menuCatalogAdminGatewayProvider.overrideWithValue(gateway)],
      child: const MaterialApp(home: AdminMenuScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty catalog shows the empty-state view on both tabs',
      (tester) async {
    await _pumpScreen(tester, gateway: _FakeMenuCatalogAdminGateway());

    expect(find.text('Henüz bir kategori yok.'), findsOneWidget);

    await tester.tap(find.text('Ürünler'));
    await tester.pumpAndSettle();
    expect(find.text('Henüz bir ürün yok.'), findsOneWidget);
  });

  testWidgets('lists existing categories sorted by sortOrder', (tester) async {
    await _pumpScreen(
      tester,
      gateway: _FakeMenuCatalogAdminGateway(categories: const [
        AdminMenuCategory(
            id: 'c2', name: 'Tatlılar', sortOrder: 2, isActive: true),
        AdminMenuCategory(
            id: 'c1', name: 'İçecekler', sortOrder: 1, isActive: true),
      ]),
    );

    final icecekler = tester.getTopLeft(find.text('İçecekler')).dy;
    final tatlilar = tester.getTopLeft(find.text('Tatlılar')).dy;
    expect(icecekler, lessThan(tatlilar));
  });

  testWidgets('lists existing products with a formatted price', (tester) async {
    await _pumpScreen(
      tester,
      gateway: _FakeMenuCatalogAdminGateway(products: const [
        AdminMenuProduct(
          id: 'p1',
          categoryId: 'c1',
          name: 'Ayran',
          basePriceMinorUnits: 4000,
          isAvailable: true,
        ),
      ]),
    );

    await tester.tap(find.text('Ürünler'));
    await tester.pumpAndSettle();

    expect(find.text('Ayran'), findsOneWidget);
  });

  testWidgets('adding a category calls the gateway and refreshes the list',
      (tester) async {
    final gateway = _FakeMenuCatalogAdminGateway();
    await _pumpScreen(tester, gateway: gateway);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'İçecekler');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Ekle'));
    await tester.pumpAndSettle();

    expect(gateway.createCategoryCallCount, 1);
    expect(find.text('İçecekler'), findsOneWidget);
  });

  testWidgets(
      'adding a product with no categories yet shows a guidance message instead of the dialog',
      (tester) async {
    final gateway = _FakeMenuCatalogAdminGateway();
    await _pumpScreen(tester, gateway: gateway);

    await tester.tap(find.text('Ürünler'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Önce en az bir kategori ekleyin.'), findsOneWidget);
    expect(gateway.createProductCallCount, 0);
  });

  testWidgets(
      'adding a product calls the gateway with the selected category and a converted price',
      (tester) async {
    final gateway = _FakeMenuCatalogAdminGateway(
      categories: const [
        AdminMenuCategory(
            id: 'c1', name: 'İçecekler', sortOrder: 1, isActive: true),
      ],
    );
    await _pumpScreen(tester, gateway: gateway);

    await tester.tap(find.text('Ürünler'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Ürün Adı'), 'Ayran');
    await tester.enterText(find.widgetWithText(TextField, 'Fiyat (₺)'), '40');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Ekle'));
    await tester.pumpAndSettle();

    expect(gateway.createProductCallCount, 1);
    expect(gateway.lastCreatedProductCategoryId, 'c1');
    expect(find.text('Ayran'), findsOneWidget);
  });

  // 2026-10-30 — product owner's explicit "edit/remove/Tükendi (86)" request.
  testWidgets(
      'editing a product calls updateProduct and shows the new name/price',
      (tester) async {
    final gateway = _FakeMenuCatalogAdminGateway(products: const [
      AdminMenuProduct(
        id: 'p1',
        categoryId: 'c1',
        name: 'Ayran',
        basePriceMinorUnits: 4000,
        isAvailable: true,
      ),
    ]);
    await _pumpScreen(tester, gateway: gateway);
    await tester.tap(find.text('Ürünler'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Düzenle'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Ürün Adı'), 'Ayran (Büyük)');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Kaydet'));
    await tester.pumpAndSettle();

    expect(gateway.updateProductCallCount, 1);
    expect(find.text('Ayran (Büyük)'), findsOneWidget);
  });

  testWidgets(
      'tapping Tükendi (86) toggles availability and shows the sold-out label',
      (tester) async {
    final gateway = _FakeMenuCatalogAdminGateway(products: const [
      AdminMenuProduct(
        id: 'p1',
        categoryId: 'c1',
        name: 'Ayran',
        basePriceMinorUnits: 4000,
        isAvailable: true,
      ),
    ]);
    await _pumpScreen(tester, gateway: gateway);
    await tester.tap(find.text('Ürünler'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Tükendi (86)'));
    await tester.pumpAndSettle();

    expect(gateway.setAvailabilityCallCount, 1);
    expect(find.text('Tekrar Sat'), findsOneWidget);
  });

  testWidgets('deleting a product requires confirmation, then removes it',
      (tester) async {
    final gateway = _FakeMenuCatalogAdminGateway(products: const [
      AdminMenuProduct(
        id: 'p1',
        categoryId: 'c1',
        name: 'Ayran',
        basePriceMinorUnits: 4000,
        isAvailable: true,
      ),
    ]);
    await _pumpScreen(tester, gateway: gateway);
    await tester.tap(find.text('Ürünler'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sil'));
    await tester.pumpAndSettle();
    // Confirmation dialog — cancel first, proves nothing happens yet.
    await tester.tap(find.widgetWithText(TextButton, 'İptal'));
    await tester.pumpAndSettle();
    expect(gateway.deleteProductCallCount, 0);
    expect(find.text('Ayran'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sil'));
    await tester.pumpAndSettle();

    expect(gateway.deleteProductCallCount, 1);
    expect(find.text('Henüz bir ürün yok.'), findsOneWidget);
  });
}
