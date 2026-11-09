import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/menu/domain/models/sale_unit.dart';
import 'package:abakus_one_v2/features/menu/domain/models/modifier_group.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/data/abakus_menu_catalog.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';

void main() {
  test(
      'eski menude (2026-10-28 PDF refresh oncesi) 7 kategori vardi, '
      'tamami hala AbakusMenuCatalog.categories icinde ama 6si artik '
      'isActive: false (test fixture kararliligi icin silinmedi — bkz. '
      'o kategorilerin kendi doc comment\'i)', () {
    // 16 + 2026-11-09 "Gramajlı Ürünler" (ADR-067).
    expect(AbakusMenuCatalog.categories.length, 17);
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
              // 2026-11-09 — not part of the PDF refresh (ADR-067).
              'cat_gramajli',
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

    // 9 yeni + İçecekler + 2026-11-09 Gramajlı Ürünler (ADR-067).
    expect(activeCategories.length, 11);
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
    // 2026-11-09: +3 sold-by-weight test products (ADR-067).
    expect(AbakusMenuCatalog.products.length, 79 + 92 + 4 + 3);
  });

  test(
      '2026-11-09 (ADR-067): Gramajlı Ürünler — exactly the 3 product-owner '
      'test products, all sold by kg with a per-kg basePrice', () {
    final weighed = AbakusMenuCatalog.products
        .where((p) => p.saleUnit == SaleUnit.kilogram)
        .toList();
    expect(
      {for (final p in weighed) p.name: p.basePrice},
      {
        'Dana Antrikot': 1400,
        'Kuzu Pirzola': 1650,
        'Meze Tabağı (Gramajlı)': 450,
      },
    );
    expect(weighed.every((p) => p.categoryId == 'cat_gramajli'), isTrue);
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
        // 2026-11-09 — PDF option set, BR-BOWL-011. Bowl carries its own
        // "Sos" group instead of the universal cross-sell one (asserted
        // separately below).
        'cat_bowl2' => const {
            'bowl_carb',
            'bowl_salad',
            'bowl_vegetable',
            'bowl_pickle',
            'bowl_protein_addon',
            'bowl_extra_carb',
            'bowl_extra_salad',
            'bowl_extra_vegetable',
            'bowl_fruit',
            'bowl_extra_pickle',
            'bowl_toppings',
            'bowl_cheese',
            'bowl_sauce',
          },
        // 2026-11-09 — BR-MENU-MOD-001.
        'cat_wrap2' => const {
            'fries_preference',
            'bowl_extra_vegetable',
            'bowl_sauce',
          },
        'cat_hamburger2' => const {'fries_preference', 'bowl_sauce'},
        'cat_makarna2' => const {'bowl_protein_addon', 'bowl_sauce'},
        'cat_kahvalti' || 'cat_salata2' => _extrasOnlyIds,
        _ => const <String>{},
      };
      expect(nonCrossSellGroupIds, expectedIds,
          reason:
              '${product.name} (${product.categoryId}) has unexpected modifier groups');
      expect(
        product.modifierGroups.map((g) => g.id),
        expectedIds.contains('bowl_sauce')
            ? isNot(contains('cross_sell_sauce'))
            : contains('cross_sell_sauce'),
        reason: '${product.name} has the wrong cross-sell sauce wiring',
      );
    }
  });

  group('BR-MENU-MOD-001 — category option sets (2026-11-09)', () {
    MenuProduct product(String id) =>
        AbakusMenuCatalog.products.firstWhere((p) => p.id == id);

    test(
        'Patates Tercihi on burgers and wraps: required single choice, '
        'Baharatlı / Baharatsız Patates only, both 0 TL', () {
      for (final id in ['prod_burger2_steak', 'prod_wrap2_kofte']) {
        final fries = product(id)
            .modifierGroups
            .firstWhere((g) => g.id == 'fries_preference');
        expect(fries.name, 'Patates Tercihi');
        expect(fries.selectionType, ModifierSelectionType.single);
        expect(fries.isRequired, isTrue);
        expect(fries.options.map((o) => o.name),
            ['Baharatlı Patates', 'Baharatsız Patates']);
        expect(fries.options.every((o) => o.extraPrice == 0), isTrue);
      }
    });

    test(
        'Kahvaltı and Salata have no swap group — every group is an '
        'optional multi-select extra with no free option', () {
      for (final id in ['prod_kahvalti_clasico', 'prod_salata2_veggie']) {
        for (final g in product(id).modifierGroups) {
          expect(g.selectionType, ModifierSelectionType.multiple,
              reason: '$id/${g.id}');
          expect(g.isRequired, isFalse, reason: '$id/${g.id}');
          expect(
              g.options.every((o) => o.extraPrice > 0 && !o.isDefault), isTrue,
              reason: '$id/${g.id}');
        }
      }
    });
  });

  group('BR-MENU-MOD-001 — removable ingredients (2026-11-09)', () {
    const activeCategoriesWithRecipes = {
      'cat_bowl2',
      'cat_tava',
      'cat_hamburger2',
      'cat_wrap2',
      'cat_makarna2',
      'cat_salata2',
      'cat_kahvalti',
      'cat_tartine',
    };

    test('every product in a recipe-bearing category lists its removables', () {
      for (final p in AbakusMenuCatalog.products
          .where((p) => activeCategoriesWithRecipes.contains(p.categoryId))) {
        expect(p.removableIngredients, isNotEmpty,
            reason: '${p.name} (${p.categoryId}) has no removable list');
      }
    });

    test('PDF recipe examples, main component left out', () {
      MenuProduct product(String id) =>
          AbakusMenuCatalog.products.firstWhere((p) => p.id == id);
      expect(product('prod_burger2_onion').removableIngredients,
          ['Cheddar Peyniri', 'Abaküs Sos', 'Karamelize Soğan']);
      expect(product('prod_makarna2_pipette_kofte').removableIngredients,
          ['Kremalı Pesto Sos', 'Parmesan']);
      expect(product('prod_tava_citir_tavuk').removableIngredients,
          ['Mevsim Salata', 'Basmati Pirinç Pilavı']);
      expect(product('prod_salata2_ananas').removableIngredients,
          contains('Mor Lahana Turşusu'));
    });
  });

  group('BR-BOWL-011 — PDF Bowl options (2026-11-09)', () {
    final bowl = AbakusMenuCatalog.products
        .firstWhere((p) => p.id == 'prod_bowl2_tatli_eksi_tavuk');
    ModifierGroup group(String id) =>
        bowl.modifierGroups.firstWhere((g) => g.id == id);

    test('21 ready Bowls share the same 13 groups', () {
      final bowls = AbakusMenuCatalog.products
          .where((p) => p.categoryId == 'cat_bowl2')
          .toList();
      expect(bowls, hasLength(21));
      for (final b in bowls) {
        expect(b.modifierGroups.map((g) => g.id).toList(),
            bowl.modifierGroups.map((g) => g.id).toList());
      }
    });

    test(
        'swap groups are single-select, required, max 1, default is the '
        'standard base and costs 0 TL', () {
      const defaults = {
        'bowl_carb': 'carb_basmati',
        'bowl_salad': 'salad_mevsim',
        'bowl_vegetable': 'veg_standard',
        'bowl_pickle': 'pickle_mor_lahana',
      };
      defaults.forEach((groupId, defaultId) {
        final g = group(groupId);
        expect(g.selectionType, ModifierSelectionType.single);
        expect(g.isRequired, isTrue);
        expect(g.maxSelections, 1);
        final def = g.options.where((o) => o.isDefault).toList();
        expect(def.map((o) => o.id), [defaultId]);
        expect(def.single.extraPrice, 0);
      });
    });

    test('swap prices follow the PDF "Değişim Fiyatı" column', () {
      double price(String groupId, String optionId) =>
          group(groupId).options.firstWhere((o) => o.id == optionId).extraPrice;
      expect(price('bowl_carb', 'carb_kuskus'), 0);
      expect(price('bowl_carb', 'carb_kisir'), 50);
      expect(price('bowl_salad', 'salad_roka'), 30);
      expect(price('bowl_salad', 'salad_coban'), 50);
      expect(price('bowl_vegetable', 'veg_yarim_avokado'), 80);
      expect(price('bowl_vegetable', 'veg_misir'), 0);
      expect(price('bowl_pickle', 'pickle_kapari'), 40);
    });

    test(
        'extra groups are optional multi-select, every option priced, '
        'every option selectable at once', () {
      const extraGroups = {
        'bowl_protein_addon': 20,
        'bowl_extra_carb': 9,
        'bowl_extra_salad': 5,
        'bowl_extra_vegetable': 14,
        'bowl_fruit': 5,
        'bowl_extra_pickle': 4,
        'bowl_toppings': 8,
        'bowl_cheese': 4,
        'bowl_sauce': 18,
      };
      extraGroups.forEach((groupId, count) {
        final g = group(groupId);
        expect(g.selectionType, ModifierSelectionType.multiple);
        expect(g.isRequired, isFalse);
        expect(g.options, hasLength(count), reason: groupId);
        expect(g.maxSelections, count, reason: groupId);
        expect(g.options.every((o) => o.extraPrice > 0 && !o.isDefault), isTrue,
            reason: '$groupId has a free or pre-selected option');
      });
    });

    test('sauces have no included sauce — each at its own PDF price', () {
      final sauces = group('bowl_sauce').options;
      expect(sauces.map((o) => o.extraPrice).toSet(), {20, 30, 40});
      expect(
          sauces
              .firstWhere((o) => o.id == 'bowl_sauce_sweet_chilli')
              .extraPrice,
          40);
    });
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

const _extrasOnlyIds = {
  'bowl_protein_addon',
  'bowl_extra_carb',
  'bowl_extra_salad',
  'bowl_extra_vegetable',
  'bowl_fruit',
  'bowl_extra_pickle',
  'bowl_toppings',
  'bowl_cheese',
  'bowl_sauce',
};
