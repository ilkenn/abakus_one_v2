import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/domain/models/modifier_group.dart';
import 'package:abakus_one_v2/features/menu/domain/models/modifier_option.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/product_detail_screen.dart';

const _sauceGroup = ModifierGroup(
  id: 'test_sauce',
  name: 'Sos',
  selectionType: ModifierSelectionType.single,
  isRequired: true,
  minSelections: 1,
  maxSelections: 1,
  options: [
    ModifierOption(id: 'test_sauce_ranch', name: 'Ranch'),
    ModifierOption(id: 'test_sauce_caesar', name: 'Caesar'),
  ],
);

const _extrasGroup = ModifierGroup(
  id: 'test_extras',
  name: 'Ekstra',
  selectionType: ModifierSelectionType.multiple,
  minSelections: 0,
  maxSelections: 2,
  options: [
    ModifierOption(id: 'test_extra_avokado', name: 'Avokado', extraPrice: 25),
    ModifierOption(id: 'test_extra_hellim', name: 'Hellim', extraPrice: 20),
  ],
);

const _testProduct = MenuProduct(
  id: 'test_prod_1',
  categoryId: 'test_cat',
  name: 'Test Bowl',
  description: 'Test aciklamasi',
  basePrice: 100,
  imageKey: 'does-not-exist',
  modifierGroups: [_sauceGroup, _extrasGroup],
);

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ProductDetailScreen(product: _testProduct)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('urun bilgileri (isim, fiyat, aciklama) dogru render edilir', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Test Bowl'), findsOneWidget);
    expect(find.text('Test aciklamasi'), findsOneWidget);
    // Fiyat hem ust bilgi blogunda hem de alt sabit toplam barinda gorunur.
    expect(find.text('100 TL'), findsWidgets);
  });

  testWidgets(
    'zorunlu modifier grubu secilmeden Sepete Ekle devre disidir (validasyon)',
    (tester) async {
      await pumpScreen(tester);

      final addButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Sepete Ekle'));
      expect(addButton.onPressed, isNull);
    },
  );

  testWidgets('zorunlu sos secilince Sepete Ekle aktif olur ve fiyat degismez',
      (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Ranch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ranch'));
    await tester.pumpAndSettle();

    final addButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Sepete Ekle'));
    expect(addButton.onPressed, isNotNull);
    expect(find.text('100 TL'), findsWidgets);
  });

  testWidgets('ekstra secimi toplam fiyati dinamik olarak artirir', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Ranch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ranch'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Avokado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avokado'));
    await tester.pumpAndSettle();

    // 100 (baz) + 25 (avokado) = 125 TL toplam.
    expect(find.text('125 TL'), findsOneWidget);
  });

  testWidgets('adet artirilinca toplam fiyat carpanlı olarak guncellenir', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Ranch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ranch'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    // 2 adet x 100 TL = 200 TL.
    expect(find.text('200 TL'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets(
    'siparis notu ve secilen modifierlar sepete dogru aktarilir',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: ProductDetailScreen(product: _testProduct)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Caesar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caesar'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Hellim'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hellim'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Az baharatlı olsun lütfen',
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(ProductDetailScreen));
      final container = ProviderScope.containerOf(context);

      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Sepete Ekle'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sepete Ekle'));
      await tester.pumpAndSettle();

      final cartItems = container.read(cartProvider);
      expect(cartItems, hasLength(1));
      final item = cartItems.first;
      expect(item.name, 'Test Bowl');
      expect(item.note, 'Az baharatlı olsun lütfen');
      expect(item.selectedModifiers.map((m) => m.optionName).toSet(),
          {'Caesar', 'Hellim'});
      expect(item.totalRowPrice, 120); // 100 + 20 (Hellim), adet 1
    },
  );
}
