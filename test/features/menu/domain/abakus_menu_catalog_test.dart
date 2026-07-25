import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/menu/data/abakus_menu_catalog.dart';

void main() {
  test('gercek menude 7 kategori bulunur (gercek sitenin sekme sirasiyla)', () {
    expect(AbakusMenuCatalog.categories.length, 7);
    expect(
      AbakusMenuCatalog.categories.map((c) => c.name).toList(),
      [
        'Bowl',
        'Salata',
        'Wrap',
        'Hamburger',
        'Makarna',
        'Atıştırmalık',
        'İçecekler'
      ],
    );
  });

  test('kategori sortOrder degerleri gercek site sirasini yansitir', () {
    final sorted = [...AbakusMenuCatalog.categories]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    expect(sorted, AbakusMenuCatalog.categories);
  });

  test('gercek menuden ice aktarilan urun sayisi kaynakla birebir eslesir', () {
    // menu.html: Bowl 16 + Salata 17 + Wrap 15 + Hamburger 12 + Makarna 9 +
    // Atıştırmalık 6 + İçecekler 4 = 79 ("Çok Satanlar" ayrı bir kategori
    // değil, mevcut ürünler üzerinde bir öne çıkarma bayrağıdır).
    expect(AbakusMenuCatalog.products.length, 79);
  });

  test('her urun gecerli, bilinen bir kategoriye aittir', () {
    final categoryIds = AbakusMenuCatalog.categories.map((c) => c.id).toSet();
    for (final product in AbakusMenuCatalog.products) {
      expect(
        categoryIds.contains(product.categoryId),
        isTrue,
        reason: '${product.name} bilinmeyen kategori: ${product.categoryId}',
      );
    }
  });

  test('urun idleri benzersizdir', () {
    final ids = AbakusMenuCatalog.products.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('her kategoride en az bir temsili urun bulunur', () {
    for (final category in AbakusMenuCatalog.categories) {
      final hasProduct =
          AbakusMenuCatalog.products.any((p) => p.categoryId == category.id);
      expect(hasProduct, isTrue,
          reason: '${category.name} kategorisinde urun yok');
    }
  });

  test(
      'temsili gercek urunler isim, fiyat ve aciklamalariyla dogru ice aktarilmis',
      () {
    final abakusBurger = AbakusMenuCatalog.products
        .firstWhere((p) => p.id == 'prod_abakus_burger');
    expect(abakusBurger.name, 'Abaküs Burger');
    expect(abakusBurger.basePrice, 750);
    expect(
      abakusBurger.description,
      'Dana Bonfile, Roka, Domates, Kapya Biber, Cheddar Peyniri, Jalepeno Turşu, Acı Sos.',
    );
    expect(abakusBurger.categoryId, 'cat_hamburger');

    final cocaCola =
        AbakusMenuCatalog.products.firstWhere((p) => p.id == 'prod_cocacola');
    expect(cocaCola.name, 'CocaCola Şişe');
    expect(cocaCola.basePrice, 80);
    expect(cocaCola.categoryId, 'cat_icecekler');
  });

  test('"Cok Satanlar" ile eslesen 8 urun isFeatured olarak isaretlenmis', () {
    final featured =
        AbakusMenuCatalog.products.where((p) => p.isFeatured).toList();
    expect(featured.length, 8);
    expect(
      featured.map((p) => p.name).toSet(),
      {
        'Çıtırtı Bowl',
        'Sweet Sour Bowl',
        'Golden Harmony',
        'Cheese Burger',
        'Fettucine Beef Alfredo',
        'Asian Chicken Bowl',
        'Falafel Bowl',
        'Mexico Steak Wrap',
      },
    );
  });

  test('gercek menu urunlerinin hicbirinde uydurma modifier grubu yoktur', () {
    // Gercek site sabit-icerikli yemekler sunar; ozellestirme yalnizca
    // Bowl Builder'a ait, ayri bir konsepttir.
    for (final product in AbakusMenuCatalog.products) {
      expect(product.modifierGroups, isEmpty,
          reason: '${product.name} icin uydurulmus modifier grubu var');
    }
  });
}
