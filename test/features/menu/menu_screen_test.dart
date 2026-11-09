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

const _soldOutProduct = MenuProduct(
  id: 'test_sold_out_prod',
  categoryId: 'test_cat',
  name: 'Tükenen Test Ürün',
  description: 'Test açıklaması',
  basePrice: 40,
  imageKey: 'does-not-exist',
  isAvailable: false,
);

const _allergenicProduct = MenuProduct(
  id: 'test_allergenic_prod',
  categoryId: 'test_cat',
  name: 'Glutenli Test Ürün',
  description: 'Test açıklaması',
  basePrice: 35,
  imageKey: 'does-not-exist',
  allergens: ['gluten'],
);

const _noAllergenProduct = MenuProduct(
  id: 'test_no_allergen_prod',
  categoryId: 'test_cat',
  name: 'Alerjensiz Test Ürün',
  description: 'Test açıklaması',
  basePrice: 25,
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
    'Kendi Bowlunu Yarat karti Menu\'de yok (ADR-069: Bowl Builder kaldirildi)',
    (tester) async {
      await pumpMenuScreen(tester);

      expect(find.text('Kendi Bowlunu Yarat'), findsNothing);
    },
  );

  testWidgets('gercek kategori sekmeleri gorunur ve urun listesini filtreler', (
    tester,
  ) async {
    await pumpMenuScreen(tester);

    // Kahvaltı/Tartineler: 2026-10-28 PDF refresh'inin ilk iki aktif
    // kategorisi, kategori cip satirinda "Tümü"den sonra ilk gorunenler —
    // kaydirmaya ihtiyac olmadan test edilebilir.
    expect(find.text('Tümü'), findsOneWidget);
    expect(find.text('Kahvaltı'), findsOneWidget);
    expect(find.text('Tartineler'), findsOneWidget);

    await tester.tap(find.text('Kahvaltı'));
    await tester.pumpAndSettle();

    // Kahvaltı seciliyken gercek bir Kahvaltı urunu gorunur olmali.
    expect(find.text('Clasico'), findsOneWidget);

    await tester.tap(find.text('Tartineler'));
    await tester.pumpAndSettle();

    // Tartineler'e gecince Kahvaltı'ya ozel urun artik gorunmemeli.
    expect(find.text('Clasico'), findsNothing);
    expect(find.text('Pollo Croccante'), findsOneWidget);
  });

  testWidgets(
    'bir urun kartina dokununca ProductDetailScreen acilir, Hero gecisi '
    'exception firlatmaz',
    (tester) async {
      await pumpMenuScreen(tester);

      await tester.tap(find.text('Kahvaltı'));
      await tester.pumpAndSettle();
      final productCard = find.text('Clasico');
      await tester.ensureVisible(productCard);
      await tester.pumpAndSettle();
      await tester.tap(productCard);
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

  group('tukenen urun (isAvailable == false) — Self-Order QR Faz 2', () {
    testWidgets(
      'Tukendi etiketi gorunur ve hizli sepete ekle butonu devre disidir',
      (tester) async {
        container.dispose();
        container = ProviderContainer(
          overrides: [
            menuProductsProvider.overrideWithValue([_soldOutProduct]),
          ],
        );
        await pumpMenuScreen(tester);

        expect(find.text('Tükendi'), findsOneWidget);

        final addButton = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Tükendi'),
            matching: find.byType(IconButton),
          ),
        );
        expect(addButton.onPressed, isNull);
      },
    );

    testWidgets(
      'musait bir urunde Tukendi etiketi gorunmez, hizli ekle aktiftir',
      (tester) async {
        container.dispose();
        container = ProviderContainer(
          overrides: [
            menuProductsProvider.overrideWithValue([_plainProduct]),
          ],
        );
        await pumpMenuScreen(tester);

        expect(find.text('Tükendi'), findsNothing);

        final addButton = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Sepete ekle'),
            matching: find.byType(IconButton),
          ),
        );
        expect(addButton.onPressed, isNotNull);
      },
    );
  });

  group('alerjen ikonlari ve filtresi — Self-Order QR Faz 2', () {
    testWidgets(
      'bir urunun alerjenleri varsa kartinda bir ikon gosterilir',
      (tester) async {
        container.dispose();
        container = ProviderContainer(
          overrides: [
            menuProductsProvider.overrideWithValue([_allergenicProduct]),
          ],
        );
        await pumpMenuScreen(tester);

        expect(find.byTooltip('gluten'), findsOneWidget);
      },
    );

    testWidgets(
      'hicbir urunde alerjen yoksa alerjen filtre sirasi hic gorunmez',
      (tester) async {
        container.dispose();
        container = ProviderContainer(
          overrides: [
            menuProductsProvider.overrideWithValue([_noAllergenProduct]),
          ],
        );
        await pumpMenuScreen(tester);

        expect(find.text('gluten'), findsNothing);
      },
    );

    testWidgets(
      'bir alerjen filtresi secilince o alerjeni iceren urun listeden '
      'gizlenir',
      (tester) async {
        // Iki tam-boy urun karti ayni anda, kaydirmadan gorunur olmali —
        // varsayilan test yuzeyi (800x600) bunun icin yeterince uzun degil.
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        container.dispose();
        container = ProviderContainer(
          overrides: [
            menuProductsProvider.overrideWithValue(
              [_allergenicProduct, _noAllergenProduct],
            ),
          ],
        );
        await pumpMenuScreen(tester);

        expect(find.text('Glutenli Test Ürün'), findsOneWidget);
        expect(find.text('Alerjensiz Test Ürün'), findsOneWidget);

        await tester.tap(find.text('gluten'));
        await tester.pumpAndSettle();

        expect(find.text('Glutenli Test Ürün'), findsNothing);
        expect(find.text('Alerjensiz Test Ürün'), findsOneWidget);
      },
    );
  });
}
