import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/domain/models/modifier_group.dart';
import 'package:abakus_one_v2/features/menu/domain/models/modifier_option.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/menu_screen.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/product_detail_screen.dart';
import 'package:abakus_one_v2/features/navigation/presentation/providers/navigation_provider.dart';

const _modifierProduct = MenuProduct(
  id: 'test_modifier_prod',
  categoryId: 'test_cat',
  name: 'Modifierli Test Ürün',
  description: 'Test açıklaması',
  basePrice: 50,
  imageKey: 'does-not-exist',
  modifierGroups: [
    ModifierGroup(
      id: 'test_group',
      name: 'Boyut',
      selectionType: ModifierSelectionType.single,
      isRequired: true,
      minSelections: 1,
      maxSelections: 1,
      options: [
        ModifierOption(id: 'opt_small', name: 'Küçük'),
        ModifierOption(id: 'opt_large', name: 'Büyük', extraPrice: 15),
      ],
    ),
  ],
);

const _plainProduct = MenuProduct(
  id: 'test_plain_prod',
  categoryId: 'test_cat',
  name: 'Sade Test Ürün',
  description: 'Test açıklaması',
  basePrice: 30,
  imageKey: 'does-not-exist',
);

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  Future<void> pumpMenuScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MenuScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Kendi Bowlunu Yarat karti aramaya gerek olmadan Menu acilir acilmaz gorunur',
    (tester) async {
      await pumpMenuScreen(tester);

      expect(find.text('Kendi Bowlunu Yarat'), findsOneWidget);
    },
  );

  testWidgets(
    'Kendi Bowlunu Yarat kartina dokununca push degil, Build Bowl sekmesi '
    'aktif olur',
    (tester) async {
      await pumpMenuScreen(tester);

      await tester.tap(find.text('Kendi Bowlunu Yarat'));
      await tester.pumpAndSettle();

      // MenuScreen burada tek basina pump edildigi icin sekme degisimi
      // gercek bir ekran degisikligi olarak gorunmez - asil davranis
      // main_navigation_screen_test.dart'ta uctan uca dogrulaniyor. Burada
      // sadece MenuScreen'in dogru cagriyi (push degil, selectTab) yaptigini
      // dogruluyoruz.
      expect(container.read(navigationProvider), AppTab.buildBowl);
    },
  );

  testWidgets('gercek kategori sekmeleri gorunur ve urun listesini filtreler', (
    tester,
  ) async {
    await pumpMenuScreen(tester);

    expect(find.text('Tümü'), findsOneWidget);
    expect(find.text('Bowl'), findsOneWidget);
    expect(find.text('Hamburger'), findsOneWidget);

    // Tumu seciliyken gercek bir Bowl urunu gorunur olmali.
    expect(find.text('Mexifit Bowl'), findsOneWidget);

    await tester.tap(find.text('Hamburger'));
    await tester.pumpAndSettle();

    // Hamburger'a gecince Bowl'a ozel urun artik gorunmemeli.
    expect(find.text('Mexifit Bowl'), findsNothing);
    expect(find.text('Mexico Burger'), findsOneWidget);
  });

  testWidgets(
    'bir urun kartina dokununca ProductDetailScreen acilir, Hero gecisi '
    'exception firlatmaz',
    (tester) async {
      await pumpMenuScreen(tester);

      await tester.tap(find.text('Mexifit Bowl'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  group('hizli sepete ekle guvenligi', () {
    testWidgets(
      'modifier grubu olmayan urunde hizli ekle dogrudan sepete ekler',
      (tester) async {
        container.dispose();
        container = ProviderContainer(
          overrides: [
            menuProductsProvider.overrideWithValue([_plainProduct]),
          ],
        );
        await pumpMenuScreen(tester);

        final addButton = find.byTooltip('Sepete ekle');
        await tester.ensureVisible(addButton);
        await tester.pumpAndSettle();
        await tester.tap(addButton);
        await tester.pumpAndSettle();

        expect(container.read(cartProvider), hasLength(1));
        expect(find.byType(ProductDetailScreen), findsNothing);
      },
    );

    testWidgets(
      'modifier grubu olan urunde hizli ekle dogrudan eklemez, Product '
      'Detail acar',
      (tester) async {
        container.dispose();
        container = ProviderContainer(
          overrides: [
            menuProductsProvider.overrideWithValue([_modifierProduct]),
          ],
        );
        await pumpMenuScreen(tester);

        final addButton = find.byTooltip('Sepete ekle');
        await tester.ensureVisible(addButton);
        await tester.pumpAndSettle();
        await tester.tap(addButton);
        await tester.pumpAndSettle();

        expect(container.read(cartProvider), isEmpty);
        expect(find.byType(ProductDetailScreen), findsOneWidget);
      },
    );
  });
}
