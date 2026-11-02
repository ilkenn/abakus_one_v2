import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/domain/services/product_pairing_service.dart';

MenuProduct _product({
  required String id,
  required String categoryId,
  String name = 'Ürün',
  bool isAvailable = true,
  bool isFeatured = false,
}) {
  return MenuProduct(
    id: id,
    categoryId: categoryId,
    name: name,
    description: 'Açıklama',
    basePrice: 50,
    imageKey: 'does-not-exist',
    isAvailable: isAvailable,
    isFeatured: isFeatured,
  );
}

void main() {
  group('ProductPairingService.suggestionsFor', () {
    test('eslenik kategorideki musait urunleri onerir', () {
      final bowl = _product(id: 'bowl_1', categoryId: 'cat_bowl2');
      final drink = _product(
          id: 'drink_1', categoryId: 'cat_icecekler', name: 'Limonata');
      final snack = _product(
        id: 'snack_1',
        categoryId: 'cat_atistirmalik2',
        name: 'Patates',
      );
      final otherBowl = _product(id: 'bowl_2', categoryId: 'cat_bowl2');

      final result = ProductPairingService.suggestionsFor(
        product: bowl,
        catalog: [bowl, drink, snack, otherBowl],
      );

      expect(result.map((p) => p.id), containsAll(['drink_1', 'snack_1']));
      expect(result.any((p) => p.id == 'bowl_2'), isFalse,
          reason: 'ayni kategorideki urun oneri olarak gelmemeli');
      expect(result.any((p) => p.id == 'bowl_1'), isFalse,
          reason: 'urunun kendisi oneri olarak gelmemeli');
    });

    test('kategori eslenik haritada yoksa bos liste doner (tahmin yapmaz)', () {
      final product = _product(id: 'p1', categoryId: 'test_cat');
      final other = _product(id: 'p2', categoryId: 'cat_icecekler');

      final result = ProductPairingService.suggestionsFor(
        product: product,
        catalog: [product, other],
      );

      expect(result, isEmpty);
    });

    test('musait olmayan urunler onerilmez', () {
      final bowl = _product(id: 'bowl_1', categoryId: 'cat_bowl2');
      final unavailableDrink = _product(
        id: 'drink_1',
        categoryId: 'cat_icecekler',
        isAvailable: false,
      );

      final result = ProductPairingService.suggestionsFor(
        product: bowl,
        catalog: [bowl, unavailableDrink],
      );

      expect(result, isEmpty);
    });

    test('one cikan urunler siralamada once gelir, sonrasinda isme gore', () {
      final bowl = _product(id: 'bowl_1', categoryId: 'cat_bowl2');
      final zDrink = _product(
        id: 'drink_z',
        categoryId: 'cat_icecekler',
        name: 'Zeytinyağlı Soda',
      );
      final aFeaturedDrink = _product(
        id: 'drink_a',
        categoryId: 'cat_icecekler',
        name: 'Ayran',
        isFeatured: true,
      );

      final result = ProductPairingService.suggestionsFor(
        product: bowl,
        catalog: [bowl, zDrink, aFeaturedDrink],
      );

      expect(result.first.id, 'drink_a');
      expect(result.last.id, 'drink_z');
    });

    test('maxSuggestions sinirini asmaz', () {
      final bowl = _product(id: 'bowl_1', categoryId: 'cat_bowl2');
      final manyDrinks = List.generate(
        10,
        (i) => _product(
            id: 'drink_$i', categoryId: 'cat_icecekler', name: 'İçecek $i'),
      );

      final result = ProductPairingService.suggestionsFor(
        product: bowl,
        catalog: [bowl, ...manyDrinks],
      );

      expect(result.length, ProductPairingService.maxSuggestions);
    });

    test('ayni girdiler her zaman ayni sonucu dondurur (deterministik)', () {
      final bowl = _product(id: 'bowl_1', categoryId: 'cat_bowl2');
      final drink = _product(id: 'drink_1', categoryId: 'cat_icecekler');
      final catalog = [bowl, drink];

      final a =
          ProductPairingService.suggestionsFor(product: bowl, catalog: catalog);
      final b =
          ProductPairingService.suggestionsFor(product: bowl, catalog: catalog);

      expect(a.map((p) => p.id), b.map((p) => p.id));
    });
  });
}
