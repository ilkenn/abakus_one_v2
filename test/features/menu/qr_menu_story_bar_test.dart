import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/product_detail_screen.dart';
import 'package:abakus_one_v2/features/menu/presentation/widgets/qr_menu_story_bar.dart';

const _special1 = MenuProduct(
  id: 'story_prod_1',
  categoryId: 'test_cat',
  name: 'Mercimek Çorbası',
  description: 'Günün çorbası',
  basePrice: 60,
  imageKey: 'does-not-exist',
  isFeatured: true,
);

const _special2 = MenuProduct(
  id: 'story_prod_2',
  categoryId: 'test_cat',
  name: 'Avokado Tost',
  description: 'Günün tostu',
  basePrice: 90,
  imageKey: 'does-not-exist',
  isFeatured: true,
);

const _soldOutSpecial = MenuProduct(
  id: 'story_prod_sold_out',
  categoryId: 'test_cat',
  name: 'Tükenen Özel',
  description: 'Günün tükenen ürünü',
  basePrice: 70,
  imageKey: 'does-not-exist',
  isFeatured: true,
  isAvailable: false,
);

void main() {
  Future<void> pumpStoryBar(
    WidgetTester tester, {
    required List<MenuProduct> featured,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          featuredMenuProductsProvider.overrideWithValue(featured),
        ],
        child: const MaterialApp(
          home: Scaffold(body: QrMenuStoryBar()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('one cikan urun yoksa hicbir sey render etmez', (tester) async {
    await pumpStoryBar(tester, featured: const []);

    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('her one cikan urun icin bir halka gosterir', (tester) async {
    await pumpStoryBar(tester, featured: const [_special1, _special2]);

    expect(
      find.bySemanticsLabel('Mercimek Çorbası, öne çıkan ürün'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Avokado Tost, öne çıkan ürün'),
      findsOneWidget,
    );
  });

  testWidgets('halka adinin ismini on plana koymaz (cakisma onleme)', (
    tester,
  ) async {
    await pumpStoryBar(tester, featured: const [_special1]);

    // Isim, ekrana dokunmadan once gorunur bir Text olarak yer almaz —
    // ayni ekranda urun adi baska bir yerde (orn. urun listesinde) tekrar
    // gorunse bile cakisma olmaz.
    expect(find.text('Mercimek Çorbası'), findsNothing);
  });

  testWidgets('halkaya dokununca odakli bir goruntuleme acilir', (
    tester,
  ) async {
    await pumpStoryBar(tester, featured: const [_special1]);

    await tester.tap(find.bySemanticsLabel('Mercimek Çorbası, öne çıkan ürün'));
    await tester.pumpAndSettle();

    expect(find.text('Mercimek Çorbası'), findsOneWidget);
    expect(find.text('60 TL'), findsOneWidget);
  });

  testWidgets('odakli goruntulemede Detaylari Gor urun detayini acar', (
    tester,
  ) async {
    await pumpStoryBar(tester, featured: const [_special1]);

    await tester.tap(find.bySemanticsLabel('Mercimek Çorbası, öne çıkan ürün'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Detayları Gör'));
    await tester.pumpAndSettle();

    expect(find.byType(ProductDetailScreen), findsOneWidget);
  });

  testWidgets(
    'tukenen (isAvailable == false) bir urunun odakli goruntulemesinde '
    'Sepete Ekle butonu yoktur, Tükendi etiketi gorunur',
    (tester) async {
      await pumpStoryBar(tester, featured: const [_soldOutSpecial]);

      await tester.tap(find.bySemanticsLabel('Tükenen Özel, öne çıkan ürün'));
      await tester.pumpAndSettle();

      expect(find.text('Sepete Ekle'), findsNothing);
      expect(find.textContaining('Tükendi'), findsOneWidget);
    },
  );
}
