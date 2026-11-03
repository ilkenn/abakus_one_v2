import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/menu/data/abakus_menu_catalog.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';

void main() {
  test(
      'eski menude (2026-10-28 PDF refresh oncesi) 7 kategori vardi, '
      'tamami hala AbakusMenuCatalog.categories icinde ama 6si artik '
      'isActive: false (test fixture kararliligi icin silinmedi — bkz. '
      'o kategorilerin kendi doc comment\'i)', () {
    expect(AbakusMenuCatalog.categories.length, 16);
    final legacy = AbakusMenuCatalog.categories
        .where((c) => const {
              'cat_bowl',
              'cat_salata',
              'cat_wrap',
              'cat_hamburger',
              'cat_makarna',
              'cat_atistirmalik',
              'cat_icecekler',
            }.contains(c.id))
        .toList();
    expect(legacy.length, 7);
    expect(
      legacy.map((c) => c.name).toList(),
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
    // İçecekler PDF refresh'te hic degismedi, hala aktif; diger 6 eski
    // kategori artik musteri menusunde gorunmuyor.
    expect(
      legacy.where((c) => c.id != 'cat_icecekler').every((c) => !c.isActive),
      isTrue,
    );
    expect(
      legacy.firstWhere((c) => c.id == 'cat_icecekler').isActive,
      isTrue,
    );
  });

  test(
      '2026-10-28 PDF refresh ile eklenen 9 yeni kategori hepsi aktif, '
      'PDF\'deki siralamayla', () {
    final refreshed = AbakusMenuCatalog.categories
        .where((c) => !const {
              'cat_bowl',
              'cat_salata',
              'cat_wrap',
              'cat_hamburger',
              'cat_makarna',
              'cat_atistirmalik',
              'cat_icecekler',
            }.contains(c.id))
        .toList();
    expect(refreshed.length, 9);
    expect(refreshed.every((c) => c.isActive), isTrue);
    expect(
      refreshed.map((c) => c.name).toList(),
      [
        'Kahvaltı',
        'Tartineler',
        "Bowl'lar",
        'Tavalar',
        'Salatalar',
        'Burgerler',
        "Wrap'ler",
        'Makarnalar',
        'Aperatifler',
      ],
    );
  });

  test(
      'menuCategoriesProvider/menuProductsProvider yalnizca aktif '
      'kategorileri ve urunlerini dondurur (eski 73 urun gizli kalir, '
      'cok satanlar listesi dahil)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final activeCategories = container.read(menuCategoriesProvider);
    final activeProducts = container.read(menuProductsProvider);
    final featured = container.read(featuredMenuProductsProvider);

    expect(activeCategories.length, 10); // 9 yeni + İçecekler
    expect(activeCategories.any((c) => c.id == 'cat_bowl'), isFalse);
    expect(activeProducts.any((p) => p.categoryId == 'cat_bowl'), isFalse);
    expect(activeProducts.any((p) => p.id == 'prod_cocacola'), isTrue);
    expect(featured.any((p) => p.name == 'Çıtırtı Bowl'), isFalse);
  });

  test('kategori sortOrder degerleri gercek site sirasini yansitir', () {
    final sorted = [...AbakusMenuCatalog.categories]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    expect(sorted, AbakusMenuCatalog.categories);
  });

  test(
      'gercek menuden ice aktarilan urun sayisi kaynakla birebir eslesir '
      '(eski 79 + 2026-10-28 PDF refresh\'in 92 yeni urunu + 2026-10-30 '
      'carpraz-satis icecek eklerinin 4 urunu)', () {
    // menu.html (eski, hala burada, isActive:false kategoriler altinda):
    // Bowl 16 + Salata 17 + Wrap 15 + Hamburger 12 + Makarna 9 +
    // Atıştırmalık 6 + İçecekler 4 (+2026-10-30: +4 yeni icecek = 8) = 79+4.
    // PDF refresh (yeni, aktif): Kahvaltı 3 + Tartineler 5 + Bowl'lar 21 +
    // Tavalar 20 + Salatalar 9 + Burgerler 9 + Wrap'ler 9 + Makarnalar 8 +
    // Aperatifler 8 = 92.
    expect(AbakusMenuCatalog.products.length, 79 + 92 + 4);
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

  test(
      'eski menudeki "Cok Satanlar" ile eslesen 8 urun hala isFeatured '
      'isaretli (raw katalogda kaliyor, sadece musteri tarafinda gizli)', () {
    final legacyFeatured = AbakusMenuCatalog.products
        .where((p) => p.isFeatured)
        .where((p) => const {
              'cat_bowl',
              'cat_salata',
              'cat_wrap',
              'cat_hamburger',
              'cat_makarna',
              'cat_atistirmalik',
              'cat_icecekler',
            }.contains(p.categoryId))
        .toList();
    expect(legacyFeatured.length, 8);
    expect(
      legacyFeatured.map((p) => p.name).toSet(),
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

  test(
      '2026-10-28 PDF refresh: 9 yeni urun (kategori basina 1) '
      'isFeatured olarak isaretlendi — toplamda 17 (eski 8 + yeni 9)', () {
    final allFeatured =
        AbakusMenuCatalog.products.where((p) => p.isFeatured).toList();
    expect(allFeatured.length, 17);
  });

  // 2026-10-30 product-configurator — corrected: the real menu's fixed
  // dishes used to carry zero modifier groups (customization was Bowl
  // Builder's own, separate concept). This is no longer true by design:
  // the product owner's explicit spec adds real Bowl carb/salad/pickle/
  // extras groups (cat_bowl2), Burger/Wrap Patates/Ketçap&Mayonez groups
  // (cat_hamburger2/cat_wrap2), and a universal "Ekstra Sos" cross-sell
  // group on every product. The "no fabricated group" spirit survives for
  // every OTHER category: none of them gained anything beyond that one
  // universal cross-sell group.
  test(
      'every product carries exactly the cross-sell sauce group plus '
      'whatever standard group its own category is specified to have — '
      'never an invented one', () {
    for (final product in AbakusMenuCatalog.products) {
      final nonCrossSellGroupIds = product.modifierGroups
          .where((g) => g.id != 'cross_sell_sauce')
          .map((g) => g.id)
          .toSet();
      final expectedIds = switch (product.categoryId) {
        'cat_bowl2' => const {
            'bowl_carb',
            'bowl_salad',
            'bowl_pickle',
            'bowl_extras',
            // 2026-11-03 — product owner, BR-BOWL-006–008.
            'bowl_protein_addon',
            'bowl_sauce_choice',
            'bowl_toppings',
          },
        'cat_hamburger2' || 'cat_wrap2' => const {
            'fries_preference',
            'ketchup_mayo'
          },
        _ => const <String>{},
      };
      expect(nonCrossSellGroupIds, expectedIds,
          reason:
              '${product.name} (${product.categoryId}) has unexpected modifier groups');
      expect(
        product.modifierGroups.map((g) => g.id),
        contains('cross_sell_sauce'),
        reason:
            '${product.name} is missing the universal cross-sell sauce group',
      );
    }
  });

  test(
      'every Bowl product (cat_bowl2) carries the universal removable-ingredient override',
      () {
    final bowl2Products =
        AbakusMenuCatalog.products.where((p) => p.categoryId == 'cat_bowl2');
    expect(bowl2Products, isNotEmpty);
    for (final product in bowl2Products) {
      expect(
        // 2026-10-30 correction: "Mor Lahana Turşusu" removed — it now
        // lives only in the Turşu Hakkı radio group, never as a separate
        // removable-ingredient checkbox (product owner's own fix for the
        // duplicate it used to create).
        product.removableIngredients,
        ['Mısır', 'Susamlı Çörekotlu Salatalık'],
        reason:
            '${product.name} is missing the Bowl removable-ingredient override',
      );
    }
  });
}
