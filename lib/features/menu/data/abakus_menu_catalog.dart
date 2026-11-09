import '../../pos/domain/kds/kitchen_station.dart';
import '../domain/models/menu_category.dart';
import '../domain/models/menu_product.dart';
import '../domain/models/modifier_group.dart';
import '../domain/models/product_nutrition.dart';
import '../domain/models/sale_unit.dart';
import 'product_removable_ingredients.dart';
import 'standard_modifier_groups.dart';

/// THE REAL ABAKÜS MENU.
///
/// Transcribed verbatim from the restaurant's own live menu source
/// (`menu.html`, Abaküs Ortaköy) — every category, product name, price
/// (TRY), and description below is copied exactly as published, with no
/// invented, omitted, renamed, or repriced items. Category order matches
/// the real site's tab order.
///
/// The real site's "Çok Satanlar" (best sellers) tab cross-lists 8 products
/// that already exist in their real category below — it is not a distinct
/// category with its own items, so it is not imported as one. Those 8
/// products are marked `isFeatured: true` instead (see [MenuProduct]).
///
/// The real menu's fixed dishes carry no customer-facing modifier/option
/// structure on the source site (each dish is a fixed, described
/// composition) — so every product here has empty `modifierGroups`.
/// Build-your-own customization is a separate concept (`BowlBuilder`), not
/// a property of these fixed menu items.
///
/// `imageKey`s are the exact filenames referenced by the real site. Not
/// every one currently has a matching file under `assets/images/menu/` —
/// see `docs/menu_experience_architecture.md` for the full missing-image
/// report; those products correctly fall back to a placeholder via
/// `MenuImageResolver` rather than a guessed path.
abstract final class AbakusMenuCatalog {
  AbakusMenuCatalog._();

  // 2026-10-28 PDF menu refresh — these 6 categories (and the 73 real
  // products under them) are superseded by the new PDF-sourced menu below
  // (`kahvaltiCategory` onward) and turned `isActive: false` so
  // `menuCategoriesProvider`/`menuProductsProvider` stop surfacing them to
  // customers (see that provider file's own filtering logic). They are
  // deliberately NOT deleted or renumbered: ~15 Cloud Functions test files
  // (`submitTakeawayOrderRealCatalog.test.ts` and its delivery/dine-in/
  // campaign/loyalty/reservation siblings) read specific ids/prices from
  // here (via `tool/export_menu_catalog.dart`'s export) as real-catalog
  // fixtures — changing or removing any of them would break that whole
  // suite for a reason unrelated to what it actually tests. `drinkCategory`
  // is the one exception kept `isActive: true`: the PDF refresh never
  // listed drinks, so removing them from the live customer menu would be
  // an invented, unrequested change, not a faithful import.
  static const MenuCategory bowlCategory = MenuCategory(
    id: 'cat_bowl',
    name: 'Bowl',
    sortOrder: 0,
    isActive: false,
    // KDS station-based routing (2026-09-23) — always centered on a
    // cooked protein, assembled at the hot line.
    defaultStation: KitchenStation.hot,
  );
  static const MenuCategory saladCategory = MenuCategory(
    id: 'cat_salata',
    name: 'Salata',
    sortOrder: 1,
    isActive: false,
    // KDS station-based routing (2026-09-23) — cold-assembled base; any
    // grilled protein is prepped separately at the hot line before being
    // placed on the salad.
    defaultStation: KitchenStation.cold,
  );
  static const MenuCategory wrapCategory = MenuCategory(
    id: 'cat_wrap',
    name: 'Wrap',
    sortOrder: 2,
    isActive: false,
    // KDS station-based routing (2026-09-23) — grilled/fried fillings,
    // tortilla typically warmed/pressed.
    defaultStation: KitchenStation.hot,
  );
  static const MenuCategory burgerCategory = MenuCategory(
    id: 'cat_hamburger',
    name: 'Hamburger',
    sortOrder: 3,
    isActive: false,
    // KDS station-based routing (2026-09-23) — grilled patty, toasted bun.
    defaultStation: KitchenStation.hot,
  );
  static const MenuCategory pastaCategory = MenuCategory(
    id: 'cat_makarna',
    name: 'Makarna',
    sortOrder: 4,
    isActive: false,
    // KDS station-based routing (2026-09-23) — cooked-to-order hot dishes.
    defaultStation: KitchenStation.hot,
  );
  static const MenuCategory snackCategory = MenuCategory(
    id: 'cat_atistirmalik',
    name: 'Atıştırmalık',
    sortOrder: 5,
    isActive: false,
    // KDS station-based routing (2026-09-23) — fried items.
    defaultStation: KitchenStation.hot,
  );
  static const MenuCategory drinkCategory = MenuCategory(
    id: 'cat_icecekler',
    name: 'İçecekler',
    sortOrder: 6,
    isActive: true,
    // KDS station-based routing (2026-09-21).
    defaultStation: KitchenStation.beverage,
  );

  // 2026-10-28 PDF menu refresh — the real, currently-live menu. Category
  // station routing is deliberately left `null` (falls back to
  // `KitchenStation.shared`, the documented default for any unconfigured
  // category) rather than guessed: this refresh's source data never
  // specified kitchen-station assignment, and inventing one risks
  // misrouting a real kitchen ticket.
  static const MenuCategory kahvaltiCategory = MenuCategory(
    id: 'cat_kahvalti',
    name: 'Kahvaltı',
    sortOrder: 7,
    isActive: true,
  );
  static const MenuCategory tartineCategory = MenuCategory(
    id: 'cat_tartine',
    name: 'Tartineler',
    sortOrder: 8,
    isActive: true,
  );
  static const MenuCategory bowl2Category = MenuCategory(
    id: 'cat_bowl2',
    name: "Bowl'lar",
    sortOrder: 9,
    isActive: true,
  );
  static const MenuCategory tavaCategory = MenuCategory(
    id: 'cat_tava',
    name: 'Tavalar',
    sortOrder: 10,
    isActive: true,
  );
  static const MenuCategory salata2Category = MenuCategory(
    id: 'cat_salata2',
    name: 'Salatalar',
    sortOrder: 11,
    isActive: true,
  );
  static const MenuCategory hamburger2Category = MenuCategory(
    id: 'cat_hamburger2',
    name: "Burgerler",
    sortOrder: 12,
    isActive: true,
  );
  static const MenuCategory wrap2Category = MenuCategory(
    id: 'cat_wrap2',
    name: "Wrap'ler",
    sortOrder: 13,
    isActive: true,
  );
  static const MenuCategory makarna2Category = MenuCategory(
    id: 'cat_makarna2',
    name: 'Makarnalar',
    sortOrder: 14,
    isActive: true,
  );
  static const MenuCategory atistirmalik2Category = MenuCategory(
    id: 'cat_atistirmalik2',
    name: 'Aperatifler',
    sortOrder: 15,
    isActive: true,
  );

  /// ADR-067 (2026-11-09) — products sold by weight (`SaleUnit.kilogram`,
  /// `basePrice` = TL per kg). POS dine-in only for now: the server
  /// rejects them on takeaway/delivery and the customer QR menu has no
  /// weight entry yet.
  static const MenuCategory gramajliCategory = MenuCategory(
    id: 'cat_gramajli',
    name: 'Gramajlı Ürünler',
    sortOrder: 16,
    isActive: true,
  );

  static const List<MenuCategory> categories = [
    bowlCategory,
    saladCategory,
    wrapCategory,
    burgerCategory,
    pastaCategory,
    snackCategory,
    drinkCategory,
    kahvaltiCategory,
    tartineCategory,
    bowl2Category,
    tavaCategory,
    salata2Category,
    hamburger2Category,
    wrap2Category,
    makarna2Category,
    atistirmalik2Category,
    gramajliCategory,
  ];

  /// The raw, hand-authored product literals — never read directly outside
  /// this class. [products] is the real public surface: it layers the
  /// 2026-10-30 product-configurator's shared modifier groups (Bowl carb/
  /// salad/pickle/extras on `cat_bowl2`, Patates/Ketçap&Mayonez on
  /// `cat_hamburger2`/`cat_wrap2`, the cross-sell sauce group on every
  /// product) on top, so none of the ~190 literals below need editing by
  /// hand to carry them.
  static const List<MenuProduct> _rawProducts = [
    // --- Bowl (16) ---
    MenuProduct(
      id: 'prod_mexifit_bowl',
      categoryId: 'cat_bowl',
      name: 'Mexifit Bowl',
      description:
          '150 gr. Izgara Tavuk, Meksika Pilavı, Roka Salata, Yoğurt sos, Susamlı Çörek Otlu Salatalık, Kornişon Turşu.',
      basePrice: 430,
      imageKey: 'mexifit-bowl',
    ),
    MenuProduct(
      id: 'prod_meatball_bowl',
      categoryId: 'cat_bowl',
      name: 'Meatball Bowl',
      description:
          'Izgara Köfte, Çoban Salata, Basmati Pirinç Pilavı, Izgara Kapya Biber, Yoğurt Sos, Çeri Domates, Kornişon Turşu.',
      basePrice: 510,
      imageKey: 'meatball-bowl',
    ),
    MenuProduct(
      id: 'prod_citirti_bowl',
      categoryId: 'cat_bowl',
      name: 'Çıtırtı Bowl',
      description:
          'Çıtır tavuk, Pestolu Kremalı Makarna, Mevsim Salata, Susamlı Çörek Otlu Salatalık, Mısır, Mor Lahana Turşusu.',
      basePrice: 430,
      imageKey: 'citirti-bowl',
      isFeatured: true,
    ),
    MenuProduct(
      id: 'prod_falafel_bowl',
      categoryId: 'cat_bowl',
      name: 'Falafel Bowl',
      description:
          'Çıtır Falafel, Mevsim Salata, Nar (Mevsiminde), Beyaz Peynir, Ceviz, Pirinç Pilavı, Nar Ekşisi, Tahin.',
      basePrice: 430,
      imageKey: 'falafel-bowl',
      isFeatured: true,
    ),
    MenuProduct(
      id: 'prod_asian_chicken_bowl',
      categoryId: 'cat_bowl',
      name: 'Asian Chicken Bowl',
      description:
          '200 gr. Soya Soslu Tavuk, Kuskus, Mevsim Salata, Izgara Kapya Biber, Sote Mantar, Yoğurt Sos, Mor Lahana Turşusu.',
      basePrice: 510,
      imageKey: 'asian-chicken-bowl',
      isFeatured: true,
    ),
    MenuProduct(
      id: 'prod_ton_ton_bowl',
      categoryId: 'cat_bowl',
      name: 'Ton Ton Bowl',
      description:
          '120 gr. Ton Balığı, Mısır, Kuskus, Roka Salata, Çeri Domates, Zeytin, Beyaz Peynir, Kornişon Turşu.',
      basePrice: 560,
      imageKey: 'ton-ton-bowl',
    ),
    MenuProduct(
      id: 'prod_golden_harmony',
      categoryId: 'cat_bowl',
      name: 'Golden Harmony',
      description:
          '200 gr. Köri Soslu Tavuk, Mevsim Salata, Basmati pirinç pilavı, Izgara Kırmızı Yeşil Kapya Biber, Yoğurt sos, Sote Mantar.',
      basePrice: 510,
      imageKey: 'golden-harmony',
      isFeatured: true,
    ),
    MenuProduct(
      id: 'prod_breakfast_bowl',
      categoryId: 'cat_bowl',
      name: 'Breakfast Bowl',
      description:
          'Çırpılmış Yumurta (2 Adet), Mevsim Salata, Zeytin, Beyaz Peynir, Ceviz, Avokado, Mısır, Izgara Kapya Biber.',
      basePrice: 510,
      imageKey: 'breakfast-bowl',
    ),
    MenuProduct(
      id: 'prod_sweet_sour_bowl',
      categoryId: 'cat_bowl',
      name: 'Sweet Sour Bowl',
      description:
          '200 gr. Tatlı Ekşi Tavuk, Kuskus, Çoban Salata, Kornişon Turşu, Kırmızı Yeşil Kapya biber, Rende havuç, Yoğurt.',
      basePrice: 510,
      imageKey: 'sweet-sour-bowl',
      isFeatured: true,
    ),
    MenuProduct(
      id: 'prod_grill_salmon_bowl',
      categoryId: 'cat_bowl',
      name: 'Grill Salmon Bowl',
      description:
          '120 gr. - 150 gr. aralığında Izgara Somon, Kuskus, Roka Salata, Susamlı Çörekotlu Salatalık, Avokado, Mısır, Kornişon Turşu.',
      basePrice: 750,
      imageKey: 'grill-salmon-bowl',
    ),
    MenuProduct(
      id: 'prod_gronola_bowl',
      categoryId: 'cat_bowl',
      name: 'Gronola Bowl',
      description:
          'Gronola Tahıl Gevreği, Yoğurt, Kurutulmuş Meyveler, Kabak Çekirdeği, Ceviz.',
      basePrice: 600,
      imageKey: 'gronola-bowl',
    ),
    MenuProduct(
      id: 'prod_smoke_salmon_bowl',
      categoryId: 'cat_bowl',
      name: 'Smoke Salmon Bowl',
      description:
          '100 gr. Somon Füme, Basmati Pirinç Pilavı, Roka Salata, Izgara Kapya Biber, Mısır, Avokado, Mor Lahana Turşusu.',
      basePrice: 800,
      imageKey: 'smoke-salmon-bowl',
    ),
    MenuProduct(
      id: 'prod_chefs_fire',
      categoryId: 'cat_bowl',
      name: "Chef's Fire",
      description:
          '200 gr. Tatlı Acı Tavuk, Basmati Pirinç Pilavı, Meksika Fasulyesi, Susamlı Çörek Otlu Salatalık, Mısır, Jalepeno Turşu.',
      basePrice: 510,
      imageKey: 'chefs-fire',
    ),
    MenuProduct(
      id: 'prod_vegan_bowl',
      categoryId: 'cat_bowl',
      name: 'Vegan Bowl',
      description:
          'Izgara Havuç, Izgara Kabak, Izgara Biber, Kuskus, Mevsim Salata, Avokado, Mor Lahana Turşusu, Mısır, Susamlı Çörekotlu Salatalık.',
      basePrice: 430,
      imageKey: 'vegan-bowl',
    ),
    MenuProduct(
      id: 'prod_lokum_bowl',
      categoryId: 'cat_bowl',
      name: 'Lokum Bowl',
      description:
          'Izgara Bonfile, Pestolu Kremalı Makarna, Izgara Kapya Biber, Roka Salata, Sote Mantar, Mor Lahana Turşusu.',
      basePrice: 700,
      imageKey: 'lokum-bowl',
    ),
    MenuProduct(
      id: 'prod_atom_bowl',
      categoryId: 'cat_bowl',
      name: 'Atom Bowl',
      description:
          'Gronola Tahıl Gevreği, Muz, Ahududu, Böğürtlen, Yoğurt, Ananas.',
      basePrice: 650,
      imageKey: 'atom-bowl',
    ),

    // --- Salata (17) ---
    MenuProduct(
      id: 'prod_crispy_falafel_salad',
      categoryId: 'cat_salata',
      name: 'Crispy Falafel Salad',
      description:
          'Çıtır Falafel, Marul, Lolorosso, Havuç, Nar (Mevsiminde), Beyaz Peynir, Ceviz, Nar Ekşisi, Tahin.',
      basePrice: 420,
      imageKey: 'crispy-falafel-salad',
    ),
    MenuProduct(
      id: 'prod_avokado_salad',
      categoryId: 'cat_salata',
      name: 'Avokado Salad',
      description:
          'Avokado, Marul, Roka, Havuç, Lolorosso, Çeri Domates, Parmesan Peyniri, Kabak Çekirdeği, Zeytinyağ Limon Sos.',
      basePrice: 400,
      imageKey: 'avokado-salad',
    ),
    MenuProduct(
      id: 'prod_gavurdagi_salad',
      categoryId: 'cat_salata',
      name: 'Gavurdağı Salad',
      description:
          'Domates, Kuru Soğan, Biber, Ceviz, Nar Ekşisi, Zeytinyağ Limon Sos.',
      basePrice: 350,
      imageKey: 'gavurdagi-salad',
    ),
    MenuProduct(
      id: 'prod_grill_caesar_salad',
      categoryId: 'cat_salata',
      name: 'Grill Caesar Salad',
      description:
          'Izgara Tavuk, Marul, Roka, Caesar Sos, Kruton Ekmek, Domates, Yeşil Elma, Parmesan Peyniri.',
      basePrice: 450,
      imageKey: 'grill-caesar-salad',
    ),
    MenuProduct(
      id: 'prod_smoke_salmon_salad',
      categoryId: 'cat_salata',
      name: 'Smoke Salmon Salad',
      description:
          'Somon Füme, Marul, Roka, Lolorosso, Salatalık, Avokado, Ballı Hardal, Çeri Domates, Kapari, Zeytinyağ Limon Sos.',
      basePrice: 800,
      imageKey: 'smoke-salmon-salad',
    ),
    MenuProduct(
      id: 'prod_crispy_caesar_salad',
      categoryId: 'cat_salata',
      name: 'Crispy Caesar Salad',
      description:
          'Çıtır Tavuk, Marul, Roka, Caesar Sos, Kruton Ekmek, Yeşil Elma.',
      basePrice: 420,
      imageKey: 'crispy-caesar-salad',
    ),
    MenuProduct(
      id: 'prod_mixed_salad',
      categoryId: 'cat_salata',
      name: 'Mixed Salad',
      description:
          'Izgara Köfte, Dana Bonfile, Marul, Roka, Havuç, Lolorosso, Salatalık, Kapya Biber, Parmesan Peyniri, Zeytinyağ Limon Sos, Nar Ekşisi.',
      basePrice: 900,
      imageKey: 'mixed-salad',
    ),
    MenuProduct(
      id: 'prod_coban_salad',
      categoryId: 'cat_salata',
      name: 'Çoban Salad',
      description:
          'Domates, Soğan, Maydanoz, Salatalık, Nar Ekşisi, Zeytinyağ Limon Sos.',
      basePrice: 350,
      imageKey: 'coban-salad',
    ),
    MenuProduct(
      id: 'prod_ton_ton_salad',
      categoryId: 'cat_salata',
      name: 'Ton Ton Salad',
      description:
          'Ton Balığı, Marul, Roka, Lolorosso, Havuç, Domates, Mısır, Zeytin, Beyaz Peynir, Zeytinyağ Limon Sos.',
      basePrice: 500,
      imageKey: 'ton-ton-salad',
    ),
    MenuProduct(
      id: 'prod_moms_chicken_salad',
      categoryId: 'cat_salata',
      name: "Mom's Chicken Salad",
      description:
          'Çıtır Tavuk, Marul, Ballı Hardal, Taze Soğan, Midye Makarna, Yeşil Elma.',
      basePrice: 420,
      imageKey: 'moms-chicken-salad',
    ),
    MenuProduct(
      id: 'prod_grill_salmon_salad',
      categoryId: 'cat_salata',
      name: 'Grill Salmon Salad',
      description:
          'Izgara Somon, Marul, Roka, Kırmızı Kapya Biber, Salatalık, Parmesan Peyniri, Pesto Sos, Zeytinyağ Limon Sos.',
      basePrice: 800,
      imageKey: 'grill-salmon-salad',
    ),
    MenuProduct(
      id: 'prod_veggie_salad',
      categoryId: 'cat_salata',
      name: 'Veggie Salad',
      description:
          'Haşlanmış Yumurta (2 Adet), Marul, Lolorosso, Havuç, Zeytin, Ceviz, Beyaz Peynir, Avokado, Mısır, Izgara Kapya Biber.',
      basePrice: 480,
      imageKey: 'veggie-salad',
    ),
    MenuProduct(
      id: 'prod_pineapple_salad',
      categoryId: 'cat_salata',
      name: 'Pineapple Salad',
      description:
          'Kızarmış Ananas, Marul, Lolorosso, Havuç, Mor Lahana Turşusu, Nar Ekşisi, Zeytinyağ Limon Sos.',
      basePrice: 450,
      imageKey: 'pineapple-salad',
    ),
    MenuProduct(
      id: 'prod_akdeniz_salad',
      categoryId: 'cat_salata',
      name: 'Akdeniz Salad',
      description:
          'Marul, Roka, Lolorosso, Havuç, Domates, Mısır, Beyaz Peynir, Zeytin, Zeytinyağ Limon Sos, Nar Ekşisi.',
      basePrice: 380,
      imageKey: 'akdeniz-salad',
    ),
    MenuProduct(
      id: 'prod_lokum_salad',
      categoryId: 'cat_salata',
      name: 'Lokum Salad',
      description:
          'Dana Bonfile, Roka, Domates, Midye Makarna, Yeşil Elma, Taze Soğan, Ballı Hardal, Zeytinyağ Limon Sos.',
      basePrice: 650,
      imageKey: 'lokum-salad',
    ),
    MenuProduct(
      id: 'prod_rokato_salad',
      categoryId: 'cat_salata',
      name: 'Rokato Salad',
      description:
          'Roka, Domates, Salatalık, Parmesan Peyniri, Zeytinyağ Limon Sos.',
      basePrice: 320,
      imageKey: 'rokato-salad',
    ),
    MenuProduct(
      id: 'prod_meatball_salad',
      categoryId: 'cat_salata',
      name: 'Meatball Salad',
      description:
          'Izgara Köfte, Marul, Roka, Lolorosso, Havuç, Mısır, Domates, Salatalık, Parmesan Peyniri, Zeytinyağ Limon Sos, Nar Ekşisi.',
      basePrice: 480,
      imageKey: 'meatball-salad',
    ),

    // --- Wrap (15) ---
    MenuProduct(
      id: 'prod_egg_wrap',
      categoryId: 'cat_wrap',
      name: 'Egg Wrap',
      description:
          'Çırpılmış Yumurta, Roka, Marul, Lolorosso, Havuç, Mısır, Beyaz Peynir, Zeytin, Salatalık, Çeri Domates.',
      basePrice: 400,
      imageKey: 'egg-wrap',
    ),
    MenuProduct(
      id: 'prod_asian_chicken_wrap',
      categoryId: 'cat_wrap',
      name: 'Asian Chicken Wrap',
      description:
          '150 gr Tavuk, Kırmızı - Yeşil Kapya Biber, Mantar, Karamelize Soğan, Cheddar Peyniri, Soya Sos.',
      basePrice: 480,
      imageKey: 'asian-chicken-wrap',
    ),
    MenuProduct(
      id: 'prod_smoke_salmon_wrap',
      categoryId: 'cat_wrap',
      name: 'Smoke Salmon Wrap',
      description:
          'Somon Füme, Roka, Marul, Lolorosso, Havuç, Salatalık, Labne, Kırmızı Kapya Biber, Zeytinyağ Limon Sos.',
      basePrice: 850,
      imageKey: 'smoke-salmon-wrap',
    ),
    MenuProduct(
      id: 'prod_mexico_steak_wrap',
      categoryId: 'cat_wrap',
      name: 'Mexico Steak Wrap',
      description:
          '100 gr. Dana Bonfile, Roka, Domates, Kapya Biber, Cheddar Peyniri, Jalepeno Turşu, Acı Sos.',
      basePrice: 650,
      imageKey: 'mexico-steak-wrap',
      isFeatured: true,
    ),
    MenuProduct(
      id: 'prod_caesar_wrap',
      categoryId: 'cat_wrap',
      name: 'Caesar Wrap',
      description:
          '150 gr. Izgara Tavuk, Marul, Roka, Caesar Sos, Parmesan Peyniri, Yeşil Elma.',
      basePrice: 480,
      imageKey: 'caesar-wrap',
    ),
    MenuProduct(
      id: 'prod_crispy_chicken_wrap',
      categoryId: 'cat_wrap',
      name: 'Crispy Chicken Wrap',
      description:
          'Çıtır Tavuk, Marul, Lolorosso, Havuç, Domates, Turşu, Mısır, Cheddar Peyniri, Ballı Hardal Sos.',
      basePrice: 480,
      imageKey: 'crispy-chicken-wrap',
    ),
    MenuProduct(
      id: 'prod_avokado_wrap',
      categoryId: 'cat_wrap',
      name: 'Avokado Wrap',
      description:
          'Avokado, Roka, Salatalık, Nar, Ceviz, Beyaz Peynir, Domates.',
      basePrice: 450,
      imageKey: 'avokado-wrap',
    ),
    MenuProduct(
      id: 'prod_steak_wrap',
      categoryId: 'cat_wrap',
      name: 'Steak Wrap',
      description:
          '100 gr. Dana Bonfile, Roka, Kapya Biber, Cheddar Peyniri, Domates, Turşu, Abaküs Sos.',
      basePrice: 650,
      imageKey: 'steak-wrap',
    ),
    MenuProduct(
      id: 'prod_mexico_chicken_wrap',
      categoryId: 'cat_wrap',
      name: 'Mexico Chicken Wrap',
      description:
          '150 gr. Izgara Tavuk, Marul, Domates, Jalepeno Turşu, Cheddar Peyniri, Acı Sos.',
      basePrice: 520,
      imageKey: 'mexico-chicken-wrap',
    ),
    MenuProduct(
      id: 'prod_grill_salmon_wrap',
      categoryId: 'cat_wrap',
      name: 'Grill Salmon Wrap',
      description:
          'Izgara somon, Roka, Marul, Lolorosso, Havuç, Salatalık, Labne, Kırmızı Kapya Biber, Zeytinyağ Limon Sos.',
      basePrice: 750,
      imageKey: 'grill-salmon-wrap',
    ),
    MenuProduct(
      id: 'prod_asian_steak_wrap',
      categoryId: 'cat_wrap',
      name: 'Asian Steak Wrap',
      description:
          '100 gr. Dana Bonfile, Mantar, Kapya Biber, Karamelize Soğan, Cheddar Peyniri, Soya Sos.',
      basePrice: 650,
      imageKey: 'asian-steak-wrap',
    ),
    MenuProduct(
      id: 'prod_texas_steak_wrap',
      categoryId: 'cat_wrap',
      name: 'Texas Steak Wrap',
      description:
          '100 gr. Dana Bonfile, Roka, Domates, Parmesan Peyniri, Jalepeno Turşusu, Acı Sos.',
      basePrice: 650,
      imageKey: 'texas-steak-wrap',
    ),
    MenuProduct(
      id: 'prod_veggie_wrap',
      categoryId: 'cat_wrap',
      name: 'Veggie Wrap',
      description:
          'Çıtır Falafel, Marul, Lolorosso, Havuç, Beyaz Peynir, Ceviz, Nar, Nar Ekşisi, Tahin, Zeytinyağ Limon Sos.',
      basePrice: 480,
      imageKey: 'veggie-wrap',
    ),
    MenuProduct(
      id: 'prod_ton_ton_wrap',
      categoryId: 'cat_wrap',
      name: 'Ton Ton Wrap',
      description:
          'Ton Balığı, Marul, Roka, Havuç, Lolorosso, Mısır, Domates, Siyah Zeytin, Labne, Zeytinyağ Limon Sos.',
      basePrice: 550,
      imageKey: 'ton-ton-wrap',
    ),
    MenuProduct(
      id: 'prod_meatball_wrap',
      categoryId: 'cat_wrap',
      name: 'Meatball Wrap',
      description:
          '150 gr. Izgara Köfte, Marul, Domates, Kuru Soğan, Kapya Biber, Abaküs Sos.',
      basePrice: 550,
      imageKey: 'meatball-wrap',
    ),

    // --- Hamburger (12) ---
    MenuProduct(
      id: 'prod_mexico_burger',
      categoryId: 'cat_hamburger',
      name: 'Mexico Burger',
      description:
          'Dana hamburger köftesi, Cheddar Peyniri, Marul, Jalepeno Turşu, Acı Sos.',
      basePrice: 600,
      imageKey: 'mexico-burger',
    ),
    MenuProduct(
      id: 'prod_cheese_burger',
      categoryId: 'cat_hamburger',
      name: 'Cheese Burger',
      description:
          'Dana hamburger köftesi, karamelize soğan, domates, marul, turşu, cheddar peyniri, Abaküs Sos.',
      basePrice: 580,
      imageKey: 'cheese-burger',
      isFeatured: true,
    ),
    MenuProduct(
      id: 'prod_onion_burger',
      categoryId: 'cat_hamburger',
      name: 'Onion Burger',
      description:
          'Dana hamburger köftesi, cheddar peyniri, Karamelize Soğan, Abaküs Sos.',
      basePrice: 550,
      imageKey: 'onion-burger',
    ),
    MenuProduct(
      id: 'prod_falafel_burger',
      categoryId: 'cat_hamburger',
      name: 'Falafel Burger',
      description: 'Falafel burger köftesi, Marul, Domates, Turşu, Yoğurt Sos.',
      basePrice: 450,
      imageKey: 'falafel-burger',
    ),
    MenuProduct(
      id: 'prod_double_chicken',
      categoryId: 'cat_hamburger',
      name: 'Double Chicken',
      description:
          '2 kat Çıtır Tavuk, Marul, Cheddar Peyniri, Turşu, Ballı Hardal Sos.',
      basePrice: 500,
      imageKey: 'double-chicken',
    ),
    MenuProduct(
      id: 'prod_grill_chicken',
      categoryId: 'cat_hamburger',
      name: 'Grill Chicken',
      description:
          'Izgara Tavuk, Cheddar Peyniri, Marul, Domates, Turşu, Abaküs Sos.',
      basePrice: 480,
      imageKey: 'grill-chicken',
    ),
    MenuProduct(
      id: 'prod_swiss_mushroom_burger',
      categoryId: 'cat_hamburger',
      name: 'Swiss Mushroom Burger',
      description:
          'Dana hamburger köftesi, cheddar peyniri, Karamelize Soğan, Mantar, Ballı Hardal Sos.',
      basePrice: 620,
      imageKey: 'swiss-mushroom-burger',
    ),
    MenuProduct(
      id: 'prod_tripoli_burger',
      categoryId: 'cat_hamburger',
      name: 'Tripoli Burger',
      description:
          'Dana hamburger köftesi, cheddar peyniri, Sarısı Dağılmamış Yumurta, Dana Füme Antrikot, Acı Sos.',
      basePrice: 750,
      imageKey: 'tripoli-burger',
    ),
    MenuProduct(
      id: 'prod_steak_burger',
      categoryId: 'cat_hamburger',
      name: 'Steak Burger',
      description:
          'Dana hamburger köftesi, cheddar peyniri, dana antrikot füme, karamelize soğan, abaküs sos.',
      basePrice: 690,
      imageKey: 'steak-burger',
    ),
    MenuProduct(
      id: 'prod_smoke_house_burger',
      categoryId: 'cat_hamburger',
      name: 'Smoke House Burger',
      description:
          'Dana hamburger köftesi, cheddar peyniri, Soğan Halkası, Dana Füme Antrikot, Abaküs Sos.',
      basePrice: 640,
      imageKey: 'smoke-house-burger',
    ),
    MenuProduct(
      id: 'prod_lokum_burger',
      categoryId: 'cat_hamburger',
      name: 'Lokum Burger',
      description: 'Dana Bonfile, Cheddar Peyniri, Mantar, Karamelize Soğan.',
      basePrice: 750,
      imageKey: 'lokum-burger',
    ),
    MenuProduct(
      id: 'prod_abakus_burger',
      categoryId: 'cat_hamburger',
      name: 'Abaküs Burger',
      description:
          'Dana Bonfile, Roka, Domates, Kapya Biber, Cheddar Peyniri, Jalepeno Turşu, Acı Sos.',
      basePrice: 750,
      imageKey: 'abakus-burger',
    ),

    // --- Makarna (9) ---
    MenuProduct(
      id: 'prod_fettucine_beef_alfredo',
      categoryId: 'cat_makarna',
      name: 'Fettucine Beef Alfredo',
      description:
          'Fettucine Makarna, Dana Bonfile, Mantar, Krema, Pesto Sos, Rende Parmesan Peyniri.',
      basePrice: 550,
      imageKey: 'fettucine-beef-alfredo',
      isFeatured: true,
    ),
    MenuProduct(
      id: 'prod_fettucine_mushroom_alfredo',
      categoryId: 'cat_makarna',
      name: 'Fettucine Mushroom Alfredo',
      description:
          'Fettucine Makarna, Mantar, Krema, Pesto Sos, Rende Parmesan Peyniri.',
      basePrice: 380,
      imageKey: 'fettucine-mushroom-alfredo',
    ),
    MenuProduct(
      id: 'prod_crispy_midye',
      categoryId: 'cat_makarna',
      name: 'Crispy Midye',
      description:
          'Kremalı ve pesto soslu sosla harmanlanmış, çıtır kaplamalı midye makarna tabağı.',
      basePrice: 400,
      imageKey: 'crispy-midye',
    ),
    MenuProduct(
      id: 'prod_beef_midye',
      categoryId: 'cat_makarna',
      name: 'Beef Midye',
      description:
          'Dana bonfile parçaları, kremalı sos og parmesan ile tatlandırılmış nefis midye makarna.',
      basePrice: 530,
      imageKey: 'beef-midye',
    ),
    MenuProduct(
      id: 'prod_fettucine_crispy_chicken_alfredo',
      categoryId: 'cat_makarna',
      name: 'Fettucine Crispy Chicken Alfredo',
      description:
          'Krema ve parmesan eşliğinde, çıtır tavuk dilimleriyle sunulan Fettucine makarna.',
      basePrice: 420,
      imageKey: 'fettucine-crispy-chicken-alfredo',
    ),
    MenuProduct(
      id: 'prod_fettucine_meatball_alfredo',
      categoryId: 'cat_makarna',
      name: 'Fettucine Meatball Alfredo',
      description:
          'Izgara köfteler, mantar ve kremalı pesto soslu Fettucine makarna ziyafeti.',
      basePrice: 500,
      imageKey: 'fettucine-meatball-alfredo',
    ),
    MenuProduct(
      id: 'prod_meatball_midye',
      categoryId: 'cat_makarna',
      name: 'Meatball Midye',
      description:
          "Abaküs'ün özel baharatlı köfteleriyle harmanlanmış soslu leziz midye makarna.",
      basePrice: 480,
      imageKey: 'meatball-midye',
    ),
    MenuProduct(
      id: 'prod_fettucine_chicken_alfredo',
      categoryId: 'cat_makarna',
      name: 'Fettucine Chicken Alfredo',
      description:
          'Fettucine Makarna, Tavuk, Mantar, Krema, Pesto Sos, Rende Parmesan Peyniri.',
      basePrice: 420,
      imageKey: 'fettucine-chicken-alfredo',
    ),
    MenuProduct(
      id: 'prod_grill_chicken_midye',
      categoryId: 'cat_makarna',
      name: 'Grill Chicken Midye',
      description:
          'Izgara tavuk dilimleri ve taze krema sosuyla buluşan doyurucu midye makarna.',
      basePrice: 400,
      imageKey: 'grill-chicken-midye',
    ),

    // --- Atıştırmalık (6) ---
    MenuProduct(
      id: 'prod_truflu_patates',
      categoryId: 'cat_atistirmalik',
      name: 'Trüflü Patates',
      description:
          'Trüf yağı ve özel baharatlarla harmanlanmış çıtır patates kızartması.',
      basePrice: 300,
      imageKey: 'truflu-patates',
    ),
    MenuProduct(
      id: 'prod_sogan_halkasi',
      categoryId: 'cat_atistirmalik',
      name: 'Soğan Halkası (6 Adet)',
      description: 'Altın sarısı çıtır kaplamalı leziz soğan halkası.',
      basePrice: 200,
      imageKey: 'sogan-halkasi',
    ),
    MenuProduct(
      id: 'prod_citir_falafel',
      categoryId: 'cat_atistirmalik',
      name: 'Çıtır Falafel',
      description: 'Ev yapımı çıtır falafel köfteleri.',
      basePrice: 280,
      imageKey: 'citir-falafel',
    ),
    MenuProduct(
      id: 'prod_cheddarli_patates_kizartmasi',
      categoryId: 'cat_atistirmalik',
      name: 'Cheddarlı Patates Kızartması',
      description:
          'Altın sarısı patateslerin üzerine eritilmiş cheddar peyniri sosu.',
      basePrice: 250,
      imageKey: 'cheddarli-patates-kizartmasi',
    ),
    MenuProduct(
      id: 'prod_citir_tavuk',
      categoryId: 'cat_atistirmalik',
      name: 'Çıtır Tavuk',
      description:
          'Özel harçla kaplanarak çıtır çıtır kızartılmış taze tavuk lokmaları.',
      basePrice: 300,
      imageKey: 'citir-tavuk',
    ),
    MenuProduct(
      id: 'prod_patates_kizartmasi',
      categoryId: 'cat_atistirmalik',
      name: 'Patates Kızartması',
      description: 'Çıtır altın sarısı patates kızartması.',
      basePrice: 200,
      imageKey: 'patates-kizartmasi',
    ),

    // --- İçecekler (8) ---
    MenuProduct(
      id: 'prod_acili_ayran',
      categoryId: 'cat_icecekler',
      name: 'Acılı Ayran (Spice Ayran)',
      description:
          'Abaküs mutfağından acı severler için özel baharatlı naneli ayran.',
      basePrice: 80,
      imageKey: 'acili-ayran',
    ),
    MenuProduct(
      id: 'prod_naneli_ayran',
      categoryId: 'cat_icecekler',
      name: 'Naneli Ayran (Mint Ayran)',
      description: 'Taze nane yaprakları ile çırpılmış ferahlatıcı ayran.',
      basePrice: 80,
      imageKey: 'naneli-ayran',
    ),
    MenuProduct(
      id: 'prod_eksili_ayran',
      categoryId: 'cat_icecekler',
      name: 'Ekşili Ayran (Minus Ayran)',
      description: 'Ekşi limon esintili özel ferahlık ayranı.',
      basePrice: 80,
      imageKey: 'eksili-ayran',
    ),
    MenuProduct(
      id: 'prod_cocacola',
      categoryId: 'cat_icecekler',
      name: 'CocaCola Şişe',
      description: '300 ml soğuk şişe.',
      basePrice: 80,
      imageKey: 'cocacola',
    ),
    // 2026-10-30 — product owner's explicit cross-sell drink additions
    // (exact name/price given directly, not sourced/derived).
    MenuProduct(
      id: 'prod_fuse_tea_seftali',
      categoryId: 'cat_icecekler',
      name: 'Fuse Tea Şeftali / Soğuk Çay',
      description: '',
      basePrice: 50,
      imageKey: 'fuse-tea-seftali',
    ),
    MenuProduct(
      id: 'prod_fuse_tea_limon',
      categoryId: 'cat_icecekler',
      name: 'Fuse Tea Limon / Soğuk Çay',
      description: '',
      basePrice: 50,
      imageKey: 'fuse-tea-limon',
    ),
    MenuProduct(
      id: 'prod_su_330',
      categoryId: 'cat_icecekler',
      name: 'Su (330ml Cam / Pet)',
      description: '',
      basePrice: 20,
      imageKey: 'su-330ml',
    ),
    MenuProduct(
      id: 'prod_feslegenli_ayran',
      categoryId: 'cat_icecekler',
      name: 'Ev Yapımı Fesleğenli Ayran',
      description: '',
      basePrice: 45,
      imageKey: 'feslegenli-ayran',
    ),

    // === 2026-10-28 PDF menu refresh — the real, currently-live menu ===
    // Transcribed verbatim from the restaurant's own finalized PDF menu.
    // Where the PDF gave no ingredient breakdown (Salatalar onward,
    // allergens beyond what's noted, or a gram/piece portion), the field
    // is left empty/null rather than invented — see each category's own
    // comment below.

    // --- Kahvaltı (3) ---
    MenuProduct(
      id: 'prod_kahvalti_clasico',
      categoryId: 'cat_kahvalti',
      name: 'Clasico',
      description: 'Mevsim Salata, Zeytin, Ceviz, Haşlanmış Yumurta, Beyaz '
          'Peynir, Izgara Kapya Biber, Avokado, Çeri Domates, Salatalık.',
      basePrice: 650,
      imageKey: 'kahvalti-clasico',
      // 2026-10-28 refresh — provisional "Çok Satanlar" pick, one per new
      // category; the PDF source didn't name featured items, so this is a
      // judgment call pending the owner's own choice.
      isFeatured: true,
      nutrition: ProductNutrition(calories: 610),
      // Product owner, 2026-11-03 — verified menu-PDF allergen data;
      // corrected to add 'süt' (missing from the original import).
      allergens: ['süt', 'yumurta', 'ceviz'],
    ),
    MenuProduct(
      id: 'prod_kahvalti_steak',
      categoryId: 'cat_kahvalti',
      name: 'Steak',
      description: 'Roka Salata, Dana Antrikot Füme, Omlet, Avokado, Beyaz '
          'Peynir, Izgara Kapya Biber, Zeytin.',
      basePrice: 780,
      imageKey: 'kahvalti-steak',
      nutrition: ProductNutrition(calories: 780),
      allergens: ['süt', 'yumurta'],
    ),
    MenuProduct(
      id: 'prod_kahvalti_salmon',
      categoryId: 'cat_kahvalti',
      name: 'Salmon',
      description: 'Roka Salata, Salatalık, Labne, Avokado, Izgara Kapya '
          'Biber, Kabak Çekirdeği İçi, Kapari, Zeytin, Somon Füme, '
          'Dereotu, Zeytinyağ Limon.',
      basePrice: 860,
      imageKey: 'kahvalti-salmon',
      nutrition: ProductNutrition(calories: 520),
      // Product owner, 2026-11-03 — verified menu-PDF allergen data.
      allergens: ['süt', 'balık'],
    ),

    // --- Tartineler (5) ---
    MenuProduct(
      id: 'prod_tartine_pollo_croccante',
      categoryId: 'cat_tartine',
      name: 'Pollo Croccante',
      description: 'Çıtır Tavuk, Cheddar Peyniri, Ballı Hardal, Marul, '
          'Kornişon Turşu, Ekşi Mayalı Ekmek.',
      basePrice: 450,
      imageKey: 'tartine-pollo-croccante',
      nutrition: ProductNutrition(calories: 620),
      allergens: ['gluten', 'süt', 'yumurta', 'hardal'],
    ),
    MenuProduct(
      id: 'prod_tartine_verde_velluto',
      categoryId: 'cat_tartine',
      name: 'Verde Velluto',
      description: 'Avokado Ezmesi, Çırpılmış Yumurta, Hindi Füme, Mevsim '
          'Yeşillikleri, Cherry Domates, Ekşi Mayalı Ekmek.',
      basePrice: 560,
      imageKey: 'tartine-verde-velluto',
      nutrition: ProductNutrition(calories: 500),
      allergens: ['gluten', 'yumurta'],
    ),
    MenuProduct(
      id: 'prod_tartine_rosso_mattino',
      categoryId: 'cat_tartine',
      name: 'Rosso Mattino',
      description: 'Dana Antrikot Füme, Çırpılmış Yumurta, Labne & '
          'Parmesan, Mevsim Yeşillikleri, Cherry Domates, Ekşi Mayalı '
          'Ekmek.',
      basePrice: 780,
      imageKey: 'tartine-rosso-mattino',
      nutrition: ProductNutrition(calories: 580),
      allergens: ['gluten', 'süt', 'yumurta'],
    ),
    MenuProduct(
      id: 'prod_tartine_sole_di_salmone',
      categoryId: 'cat_tartine',
      name: 'Sole di Salmone',
      description: 'Somon Füme, Avokado, Haşlanmış Yumurta, Labne, Kapari, '
          'Dereotu, Ekşi Mayalı Ekmek.',
      basePrice: 860,
      imageKey: 'tartine-sole-di-salmone',
      nutrition: ProductNutrition(calories: 540),
      allergens: ['gluten', 'süt', 'yumurta', 'balık'],
    ),
    MenuProduct(
      id: 'prod_tartine_trio_di_mare',
      categoryId: 'cat_tartine',
      name: 'Trio di Mare',
      description: 'Somon Füme, Labne, Kapari, Dereotu, Ekşi Mayalı Ekmek.',
      basePrice: 920,
      imageKey: 'tartine-trio-di-mare',
      isFeatured: true,
      nutrition: ProductNutrition(calories: 650),
      allergens: ['gluten', 'süt', 'balık'],
    ),

    // --- Bowl'lar (21) --- Her kasede ortak baz: Mevsim salata, susamlı
    // çörekotlu salatalık, mor lahana turşusu, mısır, basmati pirinç
    // pilavı — PDF'de ayrı yazılmadığı için her ürün açıklamasına
    // tekrarlanmıyor, bu yorumda bir kez belirtiliyor.
    MenuProduct(
      id: 'prod_bowl2_tatli_eksi_tavuk',
      categoryId: 'cat_bowl2',
      name: 'Tatlı Ekşi Tavuk Bowl',
      description: '150g Tavuk.',
      basePrice: 520,
      imageKey: 'bowl2-tatli-eksi-tavuk',
      nutrition: ProductNutrition(calories: 560),
      // Product owner, 2026-11-03 (BR-BOWL-009) — confirmed real allergens
      // for this specific dish, not inferred from the description.
      allergens: ['gluten', 'susam'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_tatli_aci_tavuk',
      categoryId: 'cat_bowl2',
      name: 'Tatlı Acı Tavuk Bowl',
      description: '150g Tavuk.',
      basePrice: 520,
      imageKey: 'bowl2-tatli-aci-tavuk',
      nutrition: ProductNutrition(calories: 580),
      allergens: ['gluten', 'susam', 'soya'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_kremali_kekikli_tavuk',
      categoryId: 'cat_bowl2',
      name: 'Kremalı Kekikli Tavuk Bowl',
      description: '150g Tavuk.',
      basePrice: 500,
      imageKey: 'bowl2-kremali-kekikli-tavuk',
      nutrition: ProductNutrition(calories: 510),
      allergens: ['süt', 'susam'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_barbeku_soslu_tavuk',
      categoryId: 'cat_bowl2',
      name: 'Barbekü Soslu Tavuk Bowl',
      description: '150g Tavuk.',
      basePrice: 520,
      imageKey: 'bowl2-barbeku-soslu-tavuk',
      nutrition: ProductNutrition(calories: 590),
      allergens: ['gluten', 'susam', 'soya'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_aci_soslu_tavuk',
      categoryId: 'cat_bowl2',
      name: 'Acı Soslu Tavuk Bowl',
      description: '150g Tavuk.',
      basePrice: 520,
      imageKey: 'bowl2-aci-soslu-tavuk',
      nutrition: ProductNutrition(calories: 570),
      allergens: ['gluten', 'susam'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_soya_soslu_tavuk',
      categoryId: 'cat_bowl2',
      name: 'Soya Soslu Tavuk Bowl',
      description: '150g Tavuk.',
      basePrice: 520,
      imageKey: 'bowl2-soya-soslu-tavuk',
      nutrition: ProductNutrition(calories: 560),
      allergens: ['gluten', 'susam', 'soya'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_teriyaki_soslu_tavuk',
      categoryId: 'cat_bowl2',
      name: 'Teriyaki Soslu Tavuk Bowl',
      description: '150g Tavuk.',
      basePrice: 540,
      imageKey: 'bowl2-teriyaki-soslu-tavuk',
      nutrition: ProductNutrition(calories: 600),
      allergens: ['gluten', 'susam', 'soya'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_kori_soslu_tavuk',
      categoryId: 'cat_bowl2',
      name: 'Köri Soslu Tavuk Bowl',
      description: '150g Tavuk.',
      basePrice: 520,
      imageKey: 'bowl2-kori-soslu-tavuk',
      nutrition: ProductNutrition(calories: 560),
      allergens: ['gluten', 'susam', 'soya'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_kremali_mantarli_tavuk',
      categoryId: 'cat_bowl2',
      name: 'Kremalı Mantarlı Tavuk Bowl',
      description: '150g Tavuk.',
      basePrice: 520,
      imageKey: 'bowl2-kremali-mantarli-tavuk',
      // 2026-11-03 — corrected from 490 to 590 kcal, per the verified
      // menu-PDF import (product owner-confirmed).
      nutrition: ProductNutrition(calories: 590),
      allergens: ['gluten', 'susam', 'süt'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_kremali_pesto_tavuk',
      categoryId: 'cat_bowl2',
      name: 'Kremalı Pesto Soslu Tavuk Bowl',
      description: '150g Tavuk.',
      basePrice: 520,
      imageKey: 'bowl2-kremali-pesto-tavuk',
      nutrition: ProductNutrition(calories: 540),
      allergens: ['gluten', 'susam', 'süt'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_izgara_tavuk_gogsu',
      categoryId: 'cat_bowl2',
      name: 'Izgara Tavuk Göğsü Bowl',
      description: '150g Tavuk.',
      basePrice: 450,
      imageKey: 'bowl2-izgara-tavuk-gogsu',
      nutrition: ProductNutrition(calories: 500),
      allergens: ['gluten', 'susam'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_izgara_tavuk_pirzola',
      categoryId: 'cat_bowl2',
      name: 'Izgara Tavuk Pirzola Bowl',
      description: '150g Tavuk.',
      basePrice: 450,
      imageKey: 'bowl2-izgara-tavuk-pirzola',
      nutrition: ProductNutrition(calories: 450),
      allergens: ['gluten', 'susam'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_citir_tavuk',
      categoryId: 'cat_bowl2',
      name: 'Çıtır Tavuk Bowl',
      description: '150g Tavuk.',
      basePrice: 450,
      imageKey: 'bowl2-citir-tavuk',
      // 2026-11-03 — corrected from 570 to 680 kcal, per the verified
      // menu-PDF import (product owner-confirmed).
      nutrition: ProductNutrition(calories: 680),
      allergens: ['gluten', 'susam', 'süt'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_aci_soslu_dana_bonfile',
      categoryId: 'cat_bowl2',
      name: 'Acı Soslu Dana Bonfile Bowl',
      description: '150g Bonfile.',
      basePrice: 750,
      imageKey: 'bowl2-aci-soslu-dana-bonfile',
      // 2026-11-03 — corrected from 680 to 570 kcal, per the verified
      // menu-PDF import (product owner-confirmed, PDF name "Acılı Dana
      // Bonfile Bowl").
      nutrition: ProductNutrition(calories: 570),
      allergens: ['gluten', 'susam', 'süt'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_izgara_anne_koftesi',
      categoryId: 'cat_bowl2',
      name: 'Izgara Anne Köftesi Bowl',
      description: '150g Köfte.',
      basePrice: 550,
      imageKey: 'bowl2-izgara-anne-koftesi',
      nutrition: ProductNutrition(calories: 780),
      allergens: ['gluten', 'yumurta', 'susam'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_izgara_bonfile',
      categoryId: 'cat_bowl2',
      name: 'Izgara Bonfile Bowl',
      description: '150g Bonfile.',
      basePrice: 800,
      imageKey: 'bowl2-izgara-bonfile',
      nutrition: ProductNutrition(calories: 700),
      allergens: ['susam'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_izgara_somon',
      categoryId: 'cat_bowl2',
      name: 'Izgara Somon Bowl',
      description: '120-150g Somon.',
      basePrice: 850,
      imageKey: 'bowl2-izgara-somon',
      isFeatured: true,
      // 2026-11-03 — corrected from 680 to 850 kcal, per the verified
      // menu-PDF import (product owner-confirmed).
      nutrition: ProductNutrition(calories: 850),
      allergens: ['balık', 'susam'],
      portionLabel: '120-150g',
    ),
    MenuProduct(
      id: 'prod_bowl2_somon_fume',
      categoryId: 'cat_bowl2',
      name: 'Somon Füme Bowl',
      description: '100g Somon Füme.',
      basePrice: 900,
      imageKey: 'bowl2-somon-fume',
      nutrition: ProductNutrition(calories: 650),
      allergens: ['balık', 'susam'],
      portionLabel: '100g',
    ),
    MenuProduct(
      id: 'prod_bowl2_ton_baligi',
      categoryId: 'cat_bowl2',
      name: 'Ton Balığı Bowl',
      description: '120g Ton Balığı.',
      basePrice: 520,
      imageKey: 'bowl2-ton-baligi',
      // 2026-11-03 — corrected from 610 to 410 kcal, per the verified
      // menu-PDF import (product owner-confirmed, PDF name "Ton Balıklı
      // Bowl").
      nutrition: ProductNutrition(calories: 410),
      allergens: ['balık', 'susam'],
      portionLabel: '120g',
    ),
    MenuProduct(
      id: 'prod_bowl2_falafel',
      categoryId: 'cat_bowl2',
      name: 'Falafel Bowl',
      description: 'Falafel.',
      basePrice: 450,
      imageKey: 'bowl2-falafel',
      // 2026-11-03 — corrected from 720 to 500 kcal, per the verified
      // menu-PDF import (product owner-confirmed, PDF name "Çıtır Falafel
      // Bowl").
      nutrition: ProductNutrition(calories: 500),
      allergens: ['susam'],
    ),
    MenuProduct(
      id: 'prod_bowl2_izgara_sebze_mix',
      categoryId: 'cat_bowl2',
      name: 'Izgara Sebze Mix Bowl',
      description: 'Izgara Sebze Mix.',
      basePrice: 450,
      imageKey: 'bowl2-izgara-sebze-mix',
      // 2026-11-03 — corrected from 500 to 720 kcal, per the verified
      // menu-PDF import (product owner-confirmed, PDF name "Izgara Sebze
      // Bowl").
      nutrition: ProductNutrition(calories: 720),
      allergens: ['gluten', 'susam'],
    ),

    // --- Tavalar (20) --- Hepsi mevsim salata ve basmati pilav ile servis
    // edilir (PDF notu, her ürün açıklamasında tekrarlanmıyor).
    MenuProduct(
      id: 'prod_tava_citir_tavuk',
      categoryId: 'cat_tava',
      name: 'Çıtır Tavuk Tava',
      description: '',
      basePrice: 430,
      imageKey: 'tava-citir-tavuk',
      nutrition: ProductNutrition(calories: 780),
      allergens: ['gluten', 'süt'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_tava_tatli_eksi_tavuk',
      categoryId: 'cat_tava',
      name: 'Tatlı Ekşi Tavuk Tava',
      description: '',
      basePrice: 520,
      imageKey: 'tava-tatli-eksi-tavuk',
      nutrition: ProductNutrition(calories: 720),
      allergens: ['soya'],
      portionLabel: '200g',
    ),
    MenuProduct(
      id: 'prod_tava_kremali_pestolu_tavuk',
      categoryId: 'cat_tava',
      name: 'Kremalı Pestolu Tavuk Tava',
      description: '',
      basePrice: 520,
      imageKey: 'tava-kremali-pestolu-tavuk',
      nutrition: ProductNutrition(calories: 850),
      allergens: ['süt'],
      portionLabel: '200g',
    ),
    MenuProduct(
      id: 'prod_tava_kremali_mantarli_tavuk',
      categoryId: 'cat_tava',
      name: 'Kremalı Mantarlı Tavuk Tava',
      description: '',
      basePrice: 520,
      imageKey: 'tava-kremali-mantarli-tavuk',
      nutrition: ProductNutrition(calories: 820),
      allergens: ['süt'],
      portionLabel: '200g',
    ),
    MenuProduct(
      id: 'prod_tava_izgara_tavuk_gogsu',
      categoryId: 'cat_tava',
      name: 'Izgara Tavuk Göğsü Tava',
      description: '',
      basePrice: 430,
      imageKey: 'tava-izgara-tavuk-gogsu',
      nutrition: ProductNutrition(calories: 620),
      allergens: ['süt'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_tava_barbeku_soslu_tavuk',
      categoryId: 'cat_tava',
      name: 'Barbekü Soslu Tavuk Tava',
      description: '',
      basePrice: 520,
      imageKey: 'tava-barbeku-soslu-tavuk',
      nutrition: ProductNutrition(calories: 780),
      allergens: ['gluten', 'süt'],
      portionLabel: '200g',
    ),
    MenuProduct(
      id: 'prod_tava_tatli_aci_tavuk',
      categoryId: 'cat_tava',
      name: 'Tatlı Acı Tavuk Tava',
      description: '',
      basePrice: 520,
      imageKey: 'tava-tatli-aci-tavuk',
      nutrition: ProductNutrition(calories: 720),
      allergens: ['soya'],
      portionLabel: '200g',
    ),
    MenuProduct(
      id: 'prod_tava_izgara_tavuk_pirzola',
      categoryId: 'cat_tava',
      name: 'Izgara Tavuk Pirzola Tava',
      description: '',
      basePrice: 430,
      imageKey: 'tava-izgara-tavuk-pirzola',
      nutrition: ProductNutrition(calories: 850),
      allergens: ['süt'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_tava_kori_soslu_tavuk',
      categoryId: 'cat_tava',
      name: 'Köri Soslu Tavuk Tava',
      description: '',
      basePrice: 520,
      imageKey: 'tava-kori-soslu-tavuk',
      nutrition: ProductNutrition(calories: 820),
      allergens: ['süt'],
      portionLabel: '200g',
    ),
    MenuProduct(
      id: 'prod_tava_soya_soslu_tavuk',
      categoryId: 'cat_tava',
      name: 'Soya Soslu Tavuk Tava',
      description: '',
      basePrice: 500,
      imageKey: 'tava-soya-soslu-tavuk',
      nutrition: ProductNutrition(calories: 620),
      allergens: ['süt'],
      portionLabel: '200g',
    ),
    MenuProduct(
      id: 'prod_tava_acili_tavuk',
      categoryId: 'cat_tava',
      name: 'Acılı Tavuk Tava',
      description: '',
      basePrice: 520,
      imageKey: 'tava-acili-tavuk',
      nutrition: ProductNutrition(calories: 780),
      allergens: ['gluten', 'süt'],
      portionLabel: '200g',
    ),
    MenuProduct(
      id: 'prod_tava_kremali_kekikli_tavuk',
      categoryId: 'cat_tava',
      name: 'Kremalı Kekikli Tavuk Tava',
      description: '',
      basePrice: 480,
      imageKey: 'tava-kremali-kekikli-tavuk',
      nutrition: ProductNutrition(calories: 720),
      allergens: ['soya'],
      portionLabel: '200g',
    ),
    MenuProduct(
      id: 'prod_tava_ton_baligi',
      categoryId: 'cat_tava',
      name: 'Ton Balığı Tava',
      description: '',
      basePrice: 530,
      imageKey: 'tava-ton-baligi',
      nutrition: ProductNutrition(calories: 850),
      allergens: ['süt'],
      portionLabel: '120g',
    ),
    MenuProduct(
      id: 'prod_tava_somon_fume',
      categoryId: 'cat_tava',
      name: 'Somon Füme Tava',
      description: '',
      basePrice: 850,
      imageKey: 'tava-somon-fume',
      nutrition: ProductNutrition(calories: 820),
      allergens: ['süt'],
      portionLabel: '100g',
    ),
    MenuProduct(
      id: 'prod_tava_izgara_somon',
      categoryId: 'cat_tava',
      name: 'Izgara Somon Tava',
      description: '',
      basePrice: 850,
      imageKey: 'tava-izgara-somon',
      nutrition: ProductNutrition(calories: 620),
      allergens: ['süt'],
      portionLabel: '120g',
    ),
    MenuProduct(
      id: 'prod_tava_anne_koftesi',
      categoryId: 'cat_tava',
      name: 'Anne Köftesi Tava',
      description: '',
      basePrice: 520,
      imageKey: 'tava-anne-koftesi',
      nutrition: ProductNutrition(calories: 780),
      allergens: ['gluten', 'süt'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_tava_izgara_bonfile',
      categoryId: 'cat_tava',
      name: 'Izgara Bonfile Tava',
      description: '',
      basePrice: 850,
      imageKey: 'tava-izgara-bonfile',
      nutrition: ProductNutrition(calories: 720),
      allergens: ['soya'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_tava_acili_bonfile',
      categoryId: 'cat_tava',
      name: 'Acılı Bonfile Tava',
      description: '',
      basePrice: 900,
      imageKey: 'tava-acili-bonfile',
      isFeatured: true,
      nutrition: ProductNutrition(calories: 850),
      allergens: ['süt'],
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_tava_citir_falafel',
      categoryId: 'cat_tava',
      name: 'Çıtır Falafel Tava',
      description: '',
      basePrice: 480,
      imageKey: 'tava-citir-falafel',
      nutrition: ProductNutrition(calories: 820),
      allergens: ['süt'],
      portionLabel: '4 adet',
    ),
    MenuProduct(
      id: 'prod_tava_izgara_sebze_mix',
      categoryId: 'cat_tava',
      name: 'Izgara Sebze Mix Tava',
      description: '',
      basePrice: 450,
      imageKey: 'tava-izgara-sebze-mix',
      nutrition: ProductNutrition(calories: 620),
      allergens: ['süt'],
      portionLabel: '150g',
    ),

    // --- Salatalar (9) --- PDF, bu kategoriden itibaren malzeme/içerik
    // dökümü vermedi (sadece isim/fiyat/kalori) — description bu yüzden
    // bilerek boş bırakıldı, uydurulmadı.
    MenuProduct(
      id: 'prod_salata2_veggie',
      categoryId: 'cat_salata2',
      name: 'Veggie Salad',
      description: '',
      basePrice: 550,
      imageKey: 'salata2-veggie',
      // Product owner, 2026-11-03 — verified menu-PDF data states this
      // product has no allergens (explicit `[]`, not merely unconfirmed).
      nutrition: ProductNutrition(calories: 520),
    ),
    MenuProduct(
      id: 'prod_salata2_grill_caesar',
      categoryId: 'cat_salata2',
      name: 'Grill Caesar Salad',
      description: '',
      basePrice: 470,
      imageKey: 'salata2-grill-caesar',
      nutrition: ProductNutrition(calories: 680),
      allergens: ['süt', 'gluten'],
    ),
    MenuProduct(
      id: 'prod_salata2_crispy_caesar',
      categoryId: 'cat_salata2',
      name: 'Crispy Caesar Salad',
      description: '',
      basePrice: 450,
      imageKey: 'salata2-crispy-caesar',
      nutrition: ProductNutrition(calories: 720),
      allergens: ['gluten', 'süt'],
    ),
    MenuProduct(
      id: 'prod_salata2_moms_chicken',
      categoryId: 'cat_salata2',
      name: "Mom's Chicken Salad",
      description: '',
      basePrice: 450,
      imageKey: 'salata2-moms-chicken',
      nutrition: ProductNutrition(calories: 650),
      allergens: ['gluten', 'hardal'],
    ),
    MenuProduct(
      id: 'prod_salata2_crispy_falafel',
      categoryId: 'cat_salata2',
      name: 'Crispy Falafel Salad',
      description: '',
      basePrice: 450,
      imageKey: 'salata2-crispy-falafel',
      nutrition: ProductNutrition(calories: 690),
      allergens: ['gluten', 'susam'],
    ),
    MenuProduct(
      id: 'prod_salata2_smoked_salmon',
      categoryId: 'cat_salata2',
      name: 'Smoked Salmon Salad',
      description: '',
      basePrice: 850,
      imageKey: 'salata2-smoked-salmon',
      isFeatured: true,
      nutrition: ProductNutrition(calories: 560),
      allergens: ['balık'],
    ),
    MenuProduct(
      id: 'prod_salata2_ton_ton',
      categoryId: 'cat_salata2',
      name: 'Ton Ton Salad',
      description: '',
      basePrice: 560,
      imageKey: 'salata2-ton-ton',
      nutrition: ProductNutrition(calories: 540),
      allergens: ['balık', 'süt'],
    ),
    MenuProduct(
      id: 'prod_salata2_ananas',
      categoryId: 'cat_salata2',
      name: 'Ananas Salad',
      description: '',
      basePrice: 530,
      imageKey: 'salata2-ananas',
      // Product owner, 2026-11-03 — verified menu-PDF data states this
      // product has no allergens (explicit `[]`, not merely unconfirmed).
      nutrition: ProductNutrition(calories: 430),
    ),
    MenuProduct(
      id: 'prod_salata2_dana_bonfile',
      categoryId: 'cat_salata2',
      name: 'Dana Bonfile Salad',
      description: '',
      basePrice: 850,
      imageKey: 'salata2-dana-bonfile',
      nutrition: ProductNutrition(calories: 760),
      allergens: ['gluten', 'hardal'],
    ),

    // --- Burgerler (9) --- Patates ile servis edilir (PDF notu).
    // Malzeme dökümü verilmedi — description bilerek boş.
    MenuProduct(
      id: 'prod_burger2_double_chicken',
      categoryId: 'cat_hamburger2',
      name: 'Double Chicken Burger',
      description: '',
      basePrice: 650,
      imageKey: 'burger2-double-chicken',
      nutrition: ProductNutrition(calories: 820),
      allergens: ['gluten', 'süt', 'hardal'],
    ),
    MenuProduct(
      id: 'prod_burger2_izgara_tavuk',
      categoryId: 'cat_hamburger2',
      name: 'Izgara Tavuk Burger',
      description: '',
      basePrice: 600,
      imageKey: 'burger2-izgara-tavuk',
      nutrition: ProductNutrition(calories: 760),
      allergens: ['gluten', 'süt', 'hardal'],
    ),
    MenuProduct(
      id: 'prod_burger2_falafel',
      categoryId: 'cat_hamburger2',
      name: 'Falafel Burger',
      description: '',
      basePrice: 600,
      imageKey: 'burger2-falafel',
      nutrition: ProductNutrition(calories: 780),
      allergens: ['gluten', 'susam'],
    ),
    MenuProduct(
      id: 'prod_burger2_tripoli',
      categoryId: 'cat_hamburger2',
      name: 'Tripoli Burger',
      description: '',
      basePrice: 850,
      imageKey: 'burger2-tripoli',
      nutrition: ProductNutrition(calories: 900),
      allergens: ['gluten', 'süt', 'yumurta'],
    ),
    MenuProduct(
      id: 'prod_burger2_swiss_mushroom',
      categoryId: 'cat_hamburger2',
      name: 'Swiss Mushroom Burger',
      description: '',
      basePrice: 780,
      imageKey: 'burger2-swiss-mushroom',
      nutrition: ProductNutrition(calories: 880),
      allergens: ['gluten', 'süt'],
    ),
    MenuProduct(
      id: 'prod_burger2_steak',
      categoryId: 'cat_hamburger2',
      name: 'Steak Burger',
      description: '',
      basePrice: 800,
      imageKey: 'burger2-steak',
      isFeatured: true,
      nutrition: ProductNutrition(calories: 950),
      allergens: ['gluten', 'süt'],
    ),
    MenuProduct(
      id: 'prod_burger2_mexico_beef',
      categoryId: 'cat_hamburger2',
      name: 'Mexico Beef Burger',
      description: '',
      basePrice: 900,
      imageKey: 'burger2-mexico-beef',
      nutrition: ProductNutrition(calories: 920),
      allergens: ['gluten', 'süt'],
    ),
    MenuProduct(
      id: 'prod_burger2_onion',
      categoryId: 'cat_hamburger2',
      name: 'Onion Burger',
      description: '',
      basePrice: 720,
      imageKey: 'burger2-onion',
      nutrition: ProductNutrition(calories: 900),
      allergens: ['gluten', 'süt', 'hardal'],
    ),
    MenuProduct(
      id: 'prod_burger2_smoke_house',
      categoryId: 'cat_hamburger2',
      name: 'Smoke House Burger',
      description: '',
      basePrice: 850,
      imageKey: 'burger2-smoke-house',
      nutrition: ProductNutrition(calories: 980),
      allergens: ['gluten', 'süt', 'hardal'],
    ),

    // --- Wrap'ler (9) --- Patates ile servis edilir (PDF notu). PDF kalori
    // ve malzeme dökümü vermedi — nutrition null, description boş.
    MenuProduct(
      id: 'prod_wrap2_asian_chicken',
      categoryId: 'cat_wrap2',
      name: 'Asian Chicken Wrap',
      description: '',
      basePrice: 550,
      imageKey: 'wrap2-asian-chicken',
    ),
    MenuProduct(
      id: 'prod_wrap2_caesar',
      categoryId: 'cat_wrap2',
      name: 'Caesar Wrap',
      description: '',
      basePrice: 550,
      imageKey: 'wrap2-caesar',
    ),
    MenuProduct(
      id: 'prod_wrap2_citir_tavuk',
      categoryId: 'cat_wrap2',
      name: 'Çıtır Tavuk Wrap',
      description: '',
      basePrice: 550,
      imageKey: 'wrap2-citir-tavuk',
    ),
    MenuProduct(
      id: 'prod_wrap2_citir_falafel',
      categoryId: 'cat_wrap2',
      name: 'Çıtır Falafel Wrap',
      description: '',
      basePrice: 550,
      imageKey: 'wrap2-citir-falafel',
    ),
    MenuProduct(
      id: 'prod_wrap2_ton_ton',
      categoryId: 'cat_wrap2',
      name: 'Ton Ton Wrap',
      description: '',
      basePrice: 600,
      imageKey: 'wrap2-ton-ton',
    ),
    MenuProduct(
      id: 'prod_wrap2_kahvalti',
      categoryId: 'cat_wrap2',
      name: 'Kahvaltı Wrap',
      description: '',
      basePrice: 530,
      imageKey: 'wrap2-kahvalti',
    ),
    MenuProduct(
      id: 'prod_wrap2_kofte',
      categoryId: 'cat_wrap2',
      name: 'Köfte Wrap',
      description: '',
      basePrice: 680,
      imageKey: 'wrap2-kofte',
    ),
    MenuProduct(
      id: 'prod_wrap2_acili_bonfile',
      categoryId: 'cat_wrap2',
      name: 'Acılı Bonfile Wrap',
      description: '',
      basePrice: 850,
      imageKey: 'wrap2-acili-bonfile',
    ),
    MenuProduct(
      id: 'prod_wrap2_asian_steak',
      categoryId: 'cat_wrap2',
      name: 'Asian Steak Wrap',
      description: '',
      basePrice: 850,
      imageKey: 'wrap2-asian-steak',
      isFeatured: true,
    ),

    // --- Makarnalar (8) --- PDF kalori ve malzeme dökümü vermedi.
    MenuProduct(
      id: 'prod_makarna2_citir_tavuk_fettuccine',
      categoryId: 'cat_makarna2',
      name: 'Çıtır Tavuk Fettuccine',
      description: '',
      basePrice: 450,
      imageKey: 'makarna2-citir-tavuk-fettuccine',
    ),
    MenuProduct(
      id: 'prod_makarna2_kofte_fettuccine',
      categoryId: 'cat_makarna2',
      name: 'Köfte Fettuccine',
      description: '',
      basePrice: 550,
      imageKey: 'makarna2-kofte-fettuccine',
    ),
    MenuProduct(
      id: 'prod_makarna2_dana_bonfile_fettuccine',
      categoryId: 'cat_makarna2',
      name: 'Dana Bonfile Fettuccine',
      description: '',
      basePrice: 750,
      imageKey: 'makarna2-dana-bonfile-fettuccine',
      isFeatured: true,
    ),
    MenuProduct(
      id: 'prod_makarna2_fettuccine_chicken_alfredo',
      categoryId: 'cat_makarna2',
      name: 'Fettuccine Chicken Alfredo',
      description: '',
      basePrice: 480,
      imageKey: 'makarna2-fettuccine-chicken-alfredo',
    ),
    MenuProduct(
      id: 'prod_makarna2_pipette_kofte',
      categoryId: 'cat_makarna2',
      name: 'Pipette Köfte',
      description: '',
      basePrice: 520,
      imageKey: 'makarna2-pipette-kofte',
    ),
    MenuProduct(
      id: 'prod_makarna2_pipette_dana_bonfile',
      categoryId: 'cat_makarna2',
      name: 'Pipette Dana Bonfile',
      description: '',
      basePrice: 730,
      imageKey: 'makarna2-pipette-dana-bonfile',
    ),
    MenuProduct(
      id: 'prod_makarna2_pipette_citir_tavuk',
      categoryId: 'cat_makarna2',
      name: 'Pipette Çıtır Tavuk',
      description: '',
      basePrice: 430,
      imageKey: 'makarna2-pipette-citir-tavuk',
    ),
    MenuProduct(
      id: 'prod_makarna2_pipette_izgara_tavuk',
      categoryId: 'cat_makarna2',
      name: 'Pipette Izgara Tavuk',
      description: '',
      basePrice: 430,
      imageKey: 'makarna2-pipette-izgara-tavuk',
    ),

    // --- Aperatifler (8) --- PDF kalori vermedi, porsiyon bilgisi verdi.
    MenuProduct(
      id: 'prod_aperatif_patates_kizartmasi',
      categoryId: 'cat_atistirmalik2',
      name: 'Patates Kızartması',
      description: '',
      basePrice: 250,
      imageKey: 'aperatif-patates-kizartmasi',
      portionLabel: '120g',
    ),
    MenuProduct(
      id: 'prod_aperatif_tatli_patates',
      categoryId: 'cat_atistirmalik2',
      name: 'Tatlı Patates',
      description: '',
      basePrice: 450,
      imageKey: 'aperatif-tatli-patates',
      portionLabel: '120g',
    ),
    MenuProduct(
      id: 'prod_aperatif_truflu_patates',
      categoryId: 'cat_atistirmalik2',
      name: 'Trüflü Patates',
      description: '',
      basePrice: 350,
      imageKey: 'aperatif-truflu-patates',
      portionLabel: '120g',
    ),
    MenuProduct(
      id: 'prod_aperatif_cheddarli_patates',
      categoryId: 'cat_atistirmalik2',
      name: 'Cheddarlı Patates',
      description: '',
      basePrice: 350,
      imageKey: 'aperatif-cheddarli-patates',
      portionLabel: '120g',
    ),
    MenuProduct(
      id: 'prod_aperatif_citir_tavuk',
      categoryId: 'cat_atistirmalik2',
      name: 'Çıtır Tavuk',
      description: '',
      basePrice: 300,
      imageKey: 'aperatif-citir-tavuk',
      portionLabel: '150g',
    ),
    MenuProduct(
      id: 'prod_aperatif_sogan_halkasi',
      categoryId: 'cat_atistirmalik2',
      name: 'Soğan Halkası',
      description: '',
      basePrice: 250,
      imageKey: 'aperatif-sogan-halkasi',
      portionLabel: '6 adet',
    ),
    MenuProduct(
      id: 'prod_aperatif_citir_falafel',
      categoryId: 'cat_atistirmalik2',
      name: 'Çıtır Falafel',
      description: '',
      basePrice: 300,
      imageKey: 'aperatif-citir-falafel',
      portionLabel: '4 adet',
    ),
    MenuProduct(
      id: 'prod_aperatif_general_tso',
      categoryId: 'cat_atistirmalik2',
      name: 'General TSO',
      description: '',
      basePrice: 350,
      imageKey: 'aperatif-general-tso',
      isFeatured: true,
      portionLabel: '200g',
    ),
    // --- Gramajlı Ürünler (3) — ADR-067, product-owner test set 2026-11-09 ---
    MenuProduct(
      id: 'prod_gramaj_dana_antrikot',
      categoryId: 'cat_gramajli',
      name: 'Dana Antrikot',
      description: 'Gramajla satılır.',
      basePrice: 1400,
      imageKey: 'gramaj-dana-antrikot',
      saleUnit: SaleUnit.kilogram,
    ),
    MenuProduct(
      id: 'prod_gramaj_kuzu_pirzola',
      categoryId: 'cat_gramajli',
      name: 'Kuzu Pirzola',
      description: 'Gramajla satılır.',
      basePrice: 1650,
      imageKey: 'gramaj-kuzu-pirzola',
      saleUnit: SaleUnit.kilogram,
    ),
    MenuProduct(
      id: 'prod_gramaj_meze_tabagi',
      categoryId: 'cat_gramajli',
      name: 'Meze Tabağı (Gramajlı)',
      description: 'Gramajla satılır.',
      basePrice: 450,
      imageKey: 'gramaj-meze-tabagi',
      saleUnit: SaleUnit.kilogram,
    ),
  ];

  /// Real public catalog — [_rawProducts] plus the 2026-10-30 universal
  /// modifier-group layering (see [_rawProducts]'s own doc comment).
  /// Recomputed on each access (not `const`, since `MenuProduct.copyWith`
  /// isn't a const constructor) — cheap enough for ~190 products, and the
  /// only real callers (`menu_catalog_provider.dart`'s `Provider`s) cache
  /// the result via Riverpod rather than re-invoking this per rebuild.
  static List<MenuProduct> get products => [
        for (final product in _rawProducts)
          product.copyWith(
            modifierGroups: _standardModifierGroupsFor(product.categoryId) ??
                const [StandardModifierGroups.crossSellSauceGroup],
            removableIngredientsOverride:
                _removableIngredientsOverrideFor(product),
          ),
      ];

  /// The category's own option set (BR-BOWL-011, BR-MENU-MOD-001), each of
  /// which carries the PDF-priced "Sos" group in place of the universal
  /// cross-sell one; `null` for every other category, which keeps only
  /// the universal cross-sell sauce group.
  static List<ModifierGroup>? _standardModifierGroupsFor(String categoryId) {
    if (categoryId == bowl2Category.id) {
      return StandardModifierGroups.bowlModifierGroups;
    }
    if (categoryId == wrap2Category.id) {
      return StandardModifierGroups.wrapModifierGroups;
    }
    if (categoryId == hamburger2Category.id) {
      return StandardModifierGroups.burgerModifierGroups;
    }
    if (categoryId == makarna2Category.id) {
      return StandardModifierGroups.pastaModifierGroups;
    }
    if (categoryId == kahvaltiCategory.id || categoryId == salata2Category.id) {
      return StandardModifierGroups.extrasOnlyModifierGroups;
    }
    return null;
  }

  /// `null` falls back to parsing the product's own ingredient-list
  /// description (Kahvaltı, Tartine) — see `MenuProduct.removableIngredients`.
  static List<String>? _removableIngredientsOverrideFor(MenuProduct product) {
    if (product.categoryId == bowl2Category.id) {
      return StandardModifierGroups.bowlRemovableIngredients;
    }
    if (product.categoryId == tavaCategory.id) {
      return ProductRemovableIngredients.tava;
    }
    return ProductRemovableIngredients.byProductId[product.id];
  }
}
