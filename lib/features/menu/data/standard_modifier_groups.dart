import '../domain/models/modifier_group.dart';
import '../domain/models/modifier_option.dart';

/// Shared, catalog-wide modifier-group definitions for the 2026-10-30
/// product-configurator rules (ingredient removal, Bowl carb/salad/pickle
/// rights, Burger/Wrap accompaniments, cross-sell). Defined once here and
/// applied to every relevant product in `AbakusMenuCatalog` rather than
/// duplicated per product literal — all ~38 Bowl/Burger/Wrap products
/// share the exact same groups/options/prices per the product owner's
/// explicit spec, so a single shared constant is the only place a price
/// change would ever need to be made.
///
/// Every price below is exactly as the product owner specified — none are
/// derived, guessed, or sourced from anywhere else.
abstract final class StandardModifierGroups {
  StandardModifierGroups._();

  /// Bowl's "ÇIKARILACAK STANDART MALZEMELER" — a universal, fixed list
  /// for every Bowl product (`cat_bowl2`): the whole standard base
  /// (BR-BOWL-011), each removable at 0 TL without touching a swap group
  /// (product owner, 2026-11-10 — supersedes the 2026-10-30 rule that kept
  /// the pickle only in [bowlPickleGroup]). The product's main protein is
  /// appended per product by `AbakusMenuCatalog`.
  static const List<String> bowlRemovableIngredients = [
    'Basmati Pirinç Pilavı',
    'Mevsim Salata',
    'Mısır',
    'Susamlı Çörekotlu Salatalık',
    'Mor Lahana Turşusu',
  ];

  // ---------------------------------------------------------------------
  // 2026-11-09 — PDF ("Abaküs Street Food - Ayaklı Menü - A3") option set,
  // product owner's explicit rules (BR-BOWL-011):
  //
  // * Standard base of every ready Bowl: Basmati Pirinç Pilavı + Mevsim
  //   Salata + Mısır & Susamlı Çörekotlu Salatalık + Mor Lahana Turşusu.
  // * DEĞİŞİM (swap): single-select, locked to its own group (carb only
  //   swaps for carb, etc.), at most 1 per group, priced at the PDF's
  //   "Değişim Fiyatı" (free ones are 0 TL). The standard item is the
  //   default. 2026-11-10: swap groups only offer alternatives — no
  //   "… İstemiyorum" option; removing a base item is done through the
  //   "İçindekiler" chips ([bowlRemovableIngredients]).
  // * EKSTRA (add-on): multi-select, every option at the PDF's "Ekstra
  //   Fiyatı". Fruit, cheese, toppings, extra protein and sauces are
  //   extra-only (no swap right). Sauces have no free/included sauce.
  // ---------------------------------------------------------------------

  /// Karbonhidrat DEĞİŞİM — default Basmati.
  static const ModifierGroup bowlCarbGroup = ModifierGroup(
    id: 'bowl_carb',
    name: 'Karbonhidrat Değişimi',
    selectionType: ModifierSelectionType.single,
    isRequired: true,
    minSelections: 1,
    maxSelections: 1,
    options: [
      ModifierOption(
          id: 'carb_basmati', name: 'Pirinç / Basmati Pilavı', isDefault: true),
      ModifierOption(
          id: 'carb_meksika', name: 'Meksika Pilavı', extraPrice: 20),
      ModifierOption(id: 'carb_kuskus', name: 'Kuskus'),
      ModifierOption(id: 'carb_bulgur', name: 'Bulgur Pilavı'),
      ModifierOption(
          id: 'carb_kremali_makarna', name: 'Kremalı Makarna', extraPrice: 20),
      ModifierOption(
          id: 'carb_kremali_pestolu_makarna',
          name: 'Kremalı Pestolu Makarna',
          extraPrice: 30),
      ModifierOption(
          id: 'carb_kremali_korili_makarna',
          name: 'Kremalı Körili Makarna',
          extraPrice: 30),
      ModifierOption(
          id: 'carb_kremali_kekikli_makarna',
          name: 'Kremalı Kekikli Makarna',
          extraPrice: 30),
      ModifierOption(id: 'carb_kisir', name: 'Kısır', extraPrice: 50),
    ],
  );

  /// Salata DEĞİŞİM — default Mevsim Salata.
  static const ModifierGroup bowlSaladGroup = ModifierGroup(
    id: 'bowl_salad',
    name: 'Salata Değişimi',
    selectionType: ModifierSelectionType.single,
    isRequired: true,
    minSelections: 1,
    maxSelections: 1,
    options: [
      ModifierOption(
          id: 'salad_mevsim', name: 'Mevsim Salata', isDefault: true),
      ModifierOption(id: 'salad_marul', name: 'Marul'),
      ModifierOption(id: 'salad_roka', name: 'Roka', extraPrice: 30),
      ModifierOption(
          id: 'salad_roka_salata', name: 'Roka Salata', extraPrice: 40),
      ModifierOption(id: 'salad_coban', name: 'Çoban Salata', extraPrice: 50),
    ],
  );

  /// Sebze DEĞİŞİM — default is the standard base vegetables (Mısır +
  /// Susamlı Çörekotlu Salatalık); one PDF vegetable may replace them.
  static const ModifierGroup bowlVegetableGroup = ModifierGroup(
    id: 'bowl_vegetable',
    name: 'Sebze Değişimi',
    selectionType: ModifierSelectionType.single,
    isRequired: true,
    minSelections: 1,
    maxSelections: 1,
    options: [
      ModifierOption(
          id: 'veg_standard',
          name: 'Standart Sebze (Mısır + Susamlı Çörekotlu Salatalık)',
          isDefault: true),
      ModifierOption(
          id: 'veg_mantar_sote', name: 'Mantar Sote', extraPrice: 50),
      ModifierOption(
          id: 'veg_ceri_domates', name: 'Çeri Domates', extraPrice: 20),
      ModifierOption(id: 'veg_misir', name: 'Mısır'),
      ModifierOption(id: 'veg_taze_sogan', name: 'Taze Soğan', extraPrice: 20),
      ModifierOption(id: 'veg_kuru_sogan', name: 'Kuru Soğan'),
      ModifierOption(
          id: 'veg_izgara_yesil_biber',
          name: 'Izgara Yeşil Biber',
          extraPrice: 30),
      ModifierOption(
          id: 'veg_izgara_kapya', name: 'Izgara Kapya Biber', extraPrice: 40),
      ModifierOption(
          id: 'veg_kapya_biber', name: 'Kapya Biber', extraPrice: 30),
      ModifierOption(
          id: 'veg_yesil_biber', name: 'Yeşil Biber', extraPrice: 20),
      ModifierOption(
          id: 'veg_izgara_kabak', name: 'Izgara Kabak', extraPrice: 30),
      ModifierOption(
          id: 'veg_yarim_avokado', name: 'Yarım Avokado', extraPrice: 80),
      ModifierOption(id: 'veg_rende_havuc', name: 'Rende Havuç'),
      ModifierOption(
          id: 'veg_izgara_havuc', name: 'Izgara Havuç', extraPrice: 30),
      ModifierOption(
          id: 'veg_meksika_fasulyesi',
          name: 'Meksika Fasulyesi',
          extraPrice: 30),
    ],
  );

  /// Turşu DEĞİŞİM — default Mor Lahana Turşusu.
  static const ModifierGroup bowlPickleGroup = ModifierGroup(
    id: 'bowl_pickle',
    name: 'Turşu Değişimi',
    selectionType: ModifierSelectionType.single,
    isRequired: true,
    minSelections: 1,
    maxSelections: 1,
    options: [
      ModifierOption(
          id: 'pickle_mor_lahana', name: 'Mor Lahana Turşusu', isDefault: true),
      ModifierOption(
          id: 'pickle_kornison', name: 'Kornişon Turşu', extraPrice: 20),
      ModifierOption(
          id: 'pickle_jalapeno', name: 'Jalapeno Turşusu', extraPrice: 30),
      ModifierOption(id: 'pickle_kapari', name: 'Kapari', extraPrice: 40),
    ],
  );

  /// EKSTRA — Extra Protein (PDF group 1), on top of the Bowl's own
  /// protein. Extra-only.
  static const ModifierGroup bowlExtraProteinGroup = ModifierGroup(
    id: 'bowl_protein_addon',
    name: 'Ekstra Protein',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 20,
    options: [
      ModifierOption(
          id: 'protein_addon_tatli_eksi_tavuk',
          name: 'Tatlı Ekşi Tavuk',
          extraPrice: 300),
      ModifierOption(
          id: 'protein_addon_tatli_aci_tavuk',
          name: 'Tatlı Acı Tavuk',
          extraPrice: 300),
      ModifierOption(
          id: 'protein_addon_kremali_kekikli_tavuk',
          name: 'Kremalı Kekikli Tavuk',
          extraPrice: 280),
      ModifierOption(
          id: 'protein_addon_acili_tavuk',
          name: 'Acılı Tavuk',
          extraPrice: 300),
      ModifierOption(
          id: 'protein_addon_citir_tavuk',
          name: 'Çıtır Tavuk',
          extraPrice: 260),
      ModifierOption(
          id: 'protein_addon_teriyaki_tavuk',
          name: 'Teriyaki Tavuk',
          extraPrice: 300),
      ModifierOption(
          id: 'protein_addon_kremali_mantarli_tavuk',
          name: 'Kremalı Mantarlı Tavuk',
          extraPrice: 300),
      ModifierOption(
          id: 'protein_addon_korili_tavuk',
          name: 'Körili Tavuk',
          extraPrice: 300),
      ModifierOption(
          id: 'protein_addon_pestolu_tavuk',
          name: 'Pestolu Tavuk',
          extraPrice: 280),
      ModifierOption(
          id: 'protein_addon_izgara_tavuk_gogus',
          name: 'Izgara Tavuk (Göğüs)',
          extraPrice: 250),
      ModifierOption(
          id: 'protein_addon_izgara_tavuk_pirzola',
          name: 'Izgara Tavuk (Pirzola)',
          extraPrice: 250),
      ModifierOption(
          id: 'protein_addon_dana_bonfile',
          name: 'Dana Bonfile',
          extraPrice: 400),
      ModifierOption(
          id: 'protein_addon_kofte',
          name: 'Izgara Anne Köftesi',
          extraPrice: 300),
      ModifierOption(
          id: 'protein_addon_acili_dana_bonfile',
          name: 'Acılı Dana Bonfile',
          extraPrice: 450),
      ModifierOption(
          id: 'protein_addon_izgara_somon',
          name: 'Izgara Somon',
          extraPrice: 450),
      ModifierOption(
          id: 'protein_addon_ton_baligi', name: 'Ton Balığı', extraPrice: 300),
      ModifierOption(
          id: 'protein_addon_somon_fume', name: 'Somon Füme', extraPrice: 550),
      ModifierOption(
          id: 'protein_addon_falafel', name: 'Çıtır Falafel', extraPrice: 250),
      ModifierOption(
          id: 'protein_addon_izgara_sebze_mix',
          name: 'Izgara Sebze Mix',
          extraPrice: 220),
      ModifierOption(
          id: 'protein_addon_soya_soslu_tavuk',
          name: 'Soya Soslu Tavuk',
          extraPrice: 300),
    ],
  );

  /// EKSTRA — Karbonhidrat (PDF group 2, "Ekstra Fiyatı").
  static const ModifierGroup bowlExtraCarbGroup = ModifierGroup(
    id: 'bowl_extra_carb',
    name: 'Ekstra Karbonhidrat',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 9,
    options: [
      ModifierOption(
          id: 'extra_carb_basmati',
          name: 'Ekstra Basmati Pilavı',
          extraPrice: 80),
      ModifierOption(
          id: 'extra_carb_meksika',
          name: 'Ekstra Meksika Pilavı',
          extraPrice: 100),
      ModifierOption(
          id: 'extra_carb_kuskus', name: 'Ekstra Kuskus', extraPrice: 80),
      ModifierOption(
          id: 'extra_carb_bulgur',
          name: 'Ekstra Bulgur Pilavı',
          extraPrice: 80),
      ModifierOption(
          id: 'extra_carb_kremali_makarna',
          name: 'Ekstra Kremalı Makarna',
          extraPrice: 100),
      ModifierOption(
          id: 'extra_carb_kremali_pestolu_makarna',
          name: 'Ekstra Kremalı Pestolu Makarna',
          extraPrice: 120),
      ModifierOption(
          id: 'extra_carb_kremali_korili_makarna',
          name: 'Ekstra Kremalı Körili Makarna',
          extraPrice: 120),
      ModifierOption(
          id: 'extra_carb_kremali_kekikli_makarna',
          name: 'Ekstra Kremalı Kekikli Makarna',
          extraPrice: 120),
      ModifierOption(
          id: 'extra_carb_kisir', name: 'Ekstra Kısır', extraPrice: 150),
    ],
  );

  /// EKSTRA — Salata (PDF group 3, "Ekstra Fiyatı").
  static const ModifierGroup bowlExtraSaladGroup = ModifierGroup(
    id: 'bowl_extra_salad',
    name: 'Ekstra Salata',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 5,
    options: [
      ModifierOption(
          id: 'extra_salad_marul', name: 'Ekstra Marul', extraPrice: 40),
      ModifierOption(
          id: 'extra_salad_roka', name: 'Ekstra Roka', extraPrice: 50),
      ModifierOption(
          id: 'extra_salad_mevsim',
          name: 'Ekstra Mevsim Salata',
          extraPrice: 40),
      ModifierOption(
          id: 'extra_salad_roka_salata',
          name: 'Ekstra Roka Salata',
          extraPrice: 70),
      ModifierOption(
          id: 'extra_salad_coban', name: 'Ekstra Çoban Salata', extraPrice: 80),
    ],
  );

  /// EKSTRA — Sebze (PDF group 4, "Ekstra Fiyatı").
  static const ModifierGroup bowlExtraVegetableGroup = ModifierGroup(
    id: 'bowl_extra_vegetable',
    name: 'Ekstra Sebze',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 14,
    options: [
      ModifierOption(
          id: 'extra_veg_mantar_sote',
          name: 'Ekstra Mantar Sote',
          extraPrice: 80),
      ModifierOption(
          id: 'extra_veg_ceri_domates',
          name: 'Ekstra Çeri Domates',
          extraPrice: 30),
      ModifierOption(
          id: 'extra_veg_misir', name: 'Ekstra Mısır', extraPrice: 30),
      ModifierOption(
          id: 'extra_veg_taze_sogan',
          name: 'Ekstra Taze Soğan',
          extraPrice: 40),
      ModifierOption(
          id: 'extra_veg_kuru_sogan',
          name: 'Ekstra Kuru Soğan',
          extraPrice: 30),
      ModifierOption(
          id: 'extra_veg_izgara_yesil_biber',
          name: 'Ekstra Izgara Yeşil Biber',
          extraPrice: 50),
      ModifierOption(
          id: 'extra_veg_izgara_kapya',
          name: 'Ekstra Izgara Kapya Biber',
          extraPrice: 50),
      ModifierOption(
          id: 'extra_veg_kapya_biber',
          name: 'Ekstra Kapya Biber',
          extraPrice: 40),
      ModifierOption(
          id: 'extra_veg_yesil_biber',
          name: 'Ekstra Yeşil Biber',
          extraPrice: 30),
      ModifierOption(
          id: 'extra_veg_izgara_kabak',
          name: 'Ekstra Izgara Kabak',
          extraPrice: 50),
      ModifierOption(
          id: 'extra_veg_yarim_avokado',
          name: 'Ekstra Yarım Avokado',
          extraPrice: 120),
      ModifierOption(
          id: 'extra_veg_rende_havuc',
          name: 'Ekstra Rende Havuç',
          extraPrice: 30),
      ModifierOption(
          id: 'extra_veg_izgara_havuc',
          name: 'Ekstra Izgara Havuç',
          extraPrice: 50),
      ModifierOption(
          id: 'extra_veg_meksika_fasulyesi',
          name: 'Ekstra Meksika Fasulyesi',
          extraPrice: 50),
    ],
  );

  /// EKSTRA — Meyve (PDF group 5). Extra-only per the product owner's
  /// rule (no fruit in the standard base, so no swap right) — priced at
  /// the PDF's "Ekstra Fiyatı" column.
  static const ModifierGroup bowlFruitGroup = ModifierGroup(
    id: 'bowl_fruit',
    name: 'Meyve',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 5,
    options: [
      ModifierOption(
          id: 'fruit_frenk_uzumu', name: 'Frenk Üzümü', extraPrice: 120),
      ModifierOption(
          id: 'fruit_kurutulmus_uzum', name: 'Kurutulmuş Üzüm', extraPrice: 60),
      ModifierOption(
          id: 'fruit_yaban_mersini', name: 'Yaban Mersini', extraPrice: 120),
      ModifierOption(id: 'fruit_nar', name: 'Nar', extraPrice: 60),
      ModifierOption(
          id: 'fruit_kizarmis_ananas',
          name: 'Kızarmış Ananas',
          extraPrice: 150),
    ],
  );

  /// EKSTRA — Turşu (PDF group 6, "Ekstra Fiyatı").
  static const ModifierGroup bowlExtraPickleGroup = ModifierGroup(
    id: 'bowl_extra_pickle',
    name: 'Ekstra Turşu',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 4,
    options: [
      ModifierOption(
          id: 'extra_pickle_mor_lahana',
          name: 'Ekstra Mor Lahana Turşusu',
          extraPrice: 30),
      ModifierOption(
          id: 'extra_pickle_kornison',
          name: 'Ekstra Kornişon Turşu',
          extraPrice: 30),
      ModifierOption(
          id: 'extra_pickle_jalapeno',
          name: 'Ekstra Jalapeno Turşusu',
          extraPrice: 50),
      ModifierOption(
          id: 'extra_pickle_kapari', name: 'Ekstra Kapari', extraPrice: 60),
    ],
  );

  /// EKSTRA — Toppings (PDF group 7). Extra-only.
  static const ModifierGroup bowlToppingsGroup = ModifierGroup(
    id: 'bowl_toppings',
    name: 'Toppings',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 8,
    options: [
      ModifierOption(
          id: 'topping_siyah_zeytin', name: 'Siyah Zeytin', extraPrice: 50),
      ModifierOption(
          id: 'topping_yesil_zeytin', name: 'Yeşil Zeytin', extraPrice: 80),
      ModifierOption(
          id: 'topping_kabak_cekirdegi',
          name: 'Kabak Çekirdeği',
          extraPrice: 60),
      ModifierOption(id: 'topping_ceviz', name: 'Ceviz', extraPrice: 60),
      ModifierOption(
          id: 'topping_corekotu_susam',
          name: 'Çörekotu & Susam',
          extraPrice: 20),
      ModifierOption(id: 'topping_chia', name: 'Chia Tohumu', extraPrice: 90),
      ModifierOption(id: 'topping_keten', name: 'Keten Tohumu', extraPrice: 90),
      ModifierOption(id: 'topping_yogurt', name: 'Yoğurt', extraPrice: 80),
    ],
  );

  /// EKSTRA — Peynir (PDF group 8). Extra-only.
  static const ModifierGroup bowlCheeseGroup = ModifierGroup(
    id: 'bowl_cheese',
    name: 'Peynir',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 4,
    options: [
      ModifierOption(id: 'cheese_beyaz', name: 'Beyaz Peynir', extraPrice: 60),
      ModifierOption(
          id: 'cheese_cheddar', name: 'Cheddar Peyniri', extraPrice: 60),
      ModifierOption(
          id: 'cheese_parmesan', name: 'Parmesan Peyniri', extraPrice: 60),
      ModifierOption(id: 'cheese_labne', name: 'Labne Peyniri', extraPrice: 60),
    ],
  );

  /// EKSTRA — Sos (PDF group 9). Every sauce is extra at its own PDF
  /// price; there is no free/included sauce and no swap. Replaces the
  /// universal [crossSellSauceGroup] on Bowl products (see
  /// `AbakusMenuCatalog.products`), so a Bowl never shows two sauce lists
  /// with conflicting prices.
  static const ModifierGroup bowlSauceGroup = ModifierGroup(
    id: 'bowl_sauce',
    name: 'Sos',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 18,
    options: [
      ModifierOption(
          id: 'bowl_sauce_zeytinyag_limon',
          name: 'Zeytinyağ & Limon',
          extraPrice: 20),
      ModifierOption(
          id: 'bowl_sauce_uzum_sirkesi', name: 'Üzüm Sirkesi', extraPrice: 20),
      ModifierOption(
          id: 'bowl_sauce_yogurt_dipsos',
          name: 'Yoğurt Dipsos',
          extraPrice: 30),
      ModifierOption(
          id: 'bowl_sauce_sweet_sour', name: 'Sweet Sour', extraPrice: 30),
      ModifierOption(id: 'bowl_sauce_tahin', name: 'Tahin', extraPrice: 30),
      ModifierOption(
          id: 'bowl_sauce_sweet_chilli', name: 'Sweet Chilli', extraPrice: 40),
      ModifierOption(
          id: 'bowl_sauce_nar_eksisi', name: 'Nar Ekşisi', extraPrice: 20),
      ModifierOption(id: 'bowl_sauce_soya', name: 'Soya Sos', extraPrice: 20),
      ModifierOption(
          id: 'bowl_sauce_sriracha', name: 'Sriracha', extraPrice: 30),
      ModifierOption(id: 'bowl_sauce_ketcap', name: 'Ketçap', extraPrice: 20),
      ModifierOption(id: 'bowl_sauce_mayonez', name: 'Mayonez', extraPrice: 20),
      ModifierOption(
          id: 'bowl_sauce_elma_sirkesi', name: 'Elma Sirkesi', extraPrice: 20),
      ModifierOption(
          id: 'bowl_sauce_acili_mayonez',
          name: 'Acılı Mayonez',
          extraPrice: 40),
      ModifierOption(id: 'bowl_sauce_barbeku', name: 'Barbekü', extraPrice: 30),
      ModifierOption(id: 'bowl_sauce_hardal', name: 'Hardal', extraPrice: 30),
      ModifierOption(
          id: 'bowl_sauce_balsamic', name: 'Balsamic', extraPrice: 30),
      ModifierOption(
          id: 'bowl_sauce_abakus', name: 'Abaküs Sos', extraPrice: 30),
      ModifierOption(
          id: 'bowl_sauce_balli_hardal', name: 'Ballı Hardal', extraPrice: 30),
    ],
  );

  /// Every Bowl product (`cat_bowl2`) gets exactly these 13 groups, in
  /// this order: the 4 mandatory swap groups first, then the optional
  /// extras in the PDF's group order.
  static const List<ModifierGroup> bowlModifierGroups = [
    bowlCarbGroup,
    bowlSaladGroup,
    bowlVegetableGroup,
    bowlPickleGroup,
    bowlExtraProteinGroup,
    bowlExtraCarbGroup,
    bowlExtraSaladGroup,
    bowlExtraVegetableGroup,
    bowlFruitGroup,
    bowlExtraPickleGroup,
    bowlToppingsGroup,
    bowlCheeseGroup,
    bowlSauceGroup,
  ];

  /// Burger/Wrap "PATATES TERCİHİ" — mandatory single-select, every option
  /// free (BR-MENU-MOD-001; 2026-11-10: "Patates İstemiyorum" restored).
  static const ModifierGroup friesPreferenceGroup = ModifierGroup(
    id: 'fries_preference',
    name: 'Patates Tercihi',
    selectionType: ModifierSelectionType.single,
    isRequired: true,
    minSelections: 1,
    maxSelections: 1,
    options: [
      ModifierOption(
          id: 'fries_spicy', name: 'Baharatlı Patates', isDefault: true),
      ModifierOption(id: 'fries_plain', name: 'Baharatsız Patates'),
      ModifierOption(id: 'fries_none', name: 'Patates İstemiyorum'),
    ],
  );

  // ---------------------------------------------------------------------
  // 2026-11-09 — per-category option sets reusing the PDF's ingredient
  // pool (BR-MENU-MOD-001). Every category below carries the PDF-priced
  // [bowlSauceGroup] instead of the universal [crossSellSauceGroup].
  // ---------------------------------------------------------------------

  /// Wrapler (`cat_wrap2`): Ekstra Sebze, Sos, Patates Seçimi.
  static const List<ModifierGroup> wrapModifierGroups = [
    friesPreferenceGroup,
    bowlExtraVegetableGroup,
    bowlSauceGroup,
  ];

  /// Hamburgerler (`cat_hamburger2`): Patates Seçimi, Sos.
  static const List<ModifierGroup> burgerModifierGroups = [
    friesPreferenceGroup,
    bowlSauceGroup,
  ];

  /// Makarnalar (`cat_makarna2`): Ekstra Protein, Sos.
  static const List<ModifierGroup> pastaModifierGroups = [
    bowlExtraProteinGroup,
    bowlSauceGroup,
  ];

  /// Kahvaltı Tabakları (`cat_kahvalti`) and Salatalar (`cat_salata2`):
  /// no swaps at all — every Bowl group, but only its EKSTRA form.
  static const List<ModifierGroup> extrasOnlyModifierGroups = [
    bowlExtraProteinGroup,
    bowlExtraCarbGroup,
    bowlExtraSaladGroup,
    bowlExtraVegetableGroup,
    bowlFruitGroup,
    bowlExtraPickleGroup,
    bowlToppingsGroup,
    bowlCheeseGroup,
    bowlSauceGroup,
  ];

  /// "EKSTRA SOS ÖNERİSİ" — shown at the bottom of every product's
  /// selection modal/sheet (customer QR menu and POS staff entry alike),
  /// appended to every active product's own `modifierGroups` by
  /// `AbakusMenuCatalog.products` rather than duplicated per product.
  /// Optional multi-select; every option priced (no free sauce here).
  static const ModifierGroup crossSellSauceGroup = ModifierGroup(
    id: 'cross_sell_sauce',
    name: 'Ekstra Sos',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 6,
    options: [
      ModifierOption(id: 'sauce_abakus', name: 'Abaküs Sos', extraPrice: 25),
      ModifierOption(
          id: 'sauce_balli_hardal', name: 'Ballı Hardal', extraPrice: 25),
      ModifierOption(id: 'sauce_barbeku', name: 'Barbekü', extraPrice: 20),
      ModifierOption(
          id: 'sauce_acili_mayonez', name: 'Acılı Mayonez', extraPrice: 25),
      ModifierOption(id: 'sauce_sriracha', name: 'Sriracha', extraPrice: 25),
      ModifierOption(
          id: 'sauce_trufflu_mayonez', name: 'Trüflü Mayonez', extraPrice: 30),
    ],
  );
}
