import '../domain/models/menu_category.dart';
import '../domain/models/menu_product.dart';

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

  static const MenuCategory bowlCategory = MenuCategory(
    id: 'cat_bowl',
    name: 'Bowl',
    sortOrder: 0,
    isActive: true,
  );
  static const MenuCategory saladCategory = MenuCategory(
    id: 'cat_salata',
    name: 'Salata',
    sortOrder: 1,
    isActive: true,
  );
  static const MenuCategory wrapCategory = MenuCategory(
    id: 'cat_wrap',
    name: 'Wrap',
    sortOrder: 2,
    isActive: true,
  );
  static const MenuCategory burgerCategory = MenuCategory(
    id: 'cat_hamburger',
    name: 'Hamburger',
    sortOrder: 3,
    isActive: true,
  );
  static const MenuCategory pastaCategory = MenuCategory(
    id: 'cat_makarna',
    name: 'Makarna',
    sortOrder: 4,
    isActive: true,
  );
  static const MenuCategory snackCategory = MenuCategory(
    id: 'cat_atistirmalik',
    name: 'Atıştırmalık',
    sortOrder: 5,
    isActive: true,
  );
  static const MenuCategory drinkCategory = MenuCategory(
    id: 'cat_icecekler',
    name: 'İçecekler',
    sortOrder: 6,
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
  ];

  static const List<MenuProduct> products = [
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

    // --- İçecekler (4) ---
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
  ];
}
