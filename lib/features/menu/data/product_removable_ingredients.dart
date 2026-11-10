/// Per-product "Çıkarılabilir Malzeme" lists (BR-MENU-MOD-001, 2026-11-09),
/// transcribed from the recipes printed in the floor-stand menu PDF
/// ("Abaküs Street Food - Ayaklı Menü - A3"; Ananas Salata from its
/// previous edition). Removing any of them is free (0 TL).
///
/// Only products whose catalog `description` is empty are listed here:
/// Kahvaltı and Tartine products already derive their list from their own
/// ingredient-list description, and Bowls use
/// `StandardModifierGroups.bowlRemovableIngredients`.
///
/// The product's defining main component (its gram-weighted protein, pasta
/// or falafel/egg base, e.g. "150 gr. Çıtır Tavuk") is left out of
/// [byProductId] — except that, per the 2026-11-10 rule, the main protein
/// of Makarna, Bowl and Tava products IS removable (see
/// [mainProteinByProductId]). Burger patties stay non-removable.
abstract final class ProductRemovableIngredients {
  ProductRemovableIngredients._();

  /// Ketçap & Mayonez are served free with every fries-side product
  /// (Burgerler, Wrapler) and can be left off at 0 TL (2026-11-10).
  static const List<String> friesSideSauces = ['Ketçap', 'Mayonez'];

  /// Removable main protein of Makarna, Bowl and Tava products (2026-11-10),
  /// named as in the floor-stand menu PDF's recipe line. The protein-less
  /// "Izgara Sebze Mix" Bowl/Tava have no entry.
  static const Map<String, String> mainProteinByProductId = {
    // Bowl (cat_bowl2)
    'prod_bowl2_tatli_eksi_tavuk': 'Tatlı Ekşi Tavuk',
    'prod_bowl2_tatli_aci_tavuk': 'Tatlı Acı Tavuk',
    'prod_bowl2_kremali_kekikli_tavuk': 'Kremalı Kekikli Tavuk',
    'prod_bowl2_barbeku_soslu_tavuk': 'Barbekü Soslu Tavuk',
    'prod_bowl2_aci_soslu_tavuk': 'Acı Soslu Tavuk',
    'prod_bowl2_soya_soslu_tavuk': 'Soya Soslu Tavuk',
    'prod_bowl2_teriyaki_soslu_tavuk': 'Teriyaki Soslu Tavuk',
    'prod_bowl2_kori_soslu_tavuk': 'Köri Soslu Tavuk',
    'prod_bowl2_kremali_mantarli_tavuk': 'Kremalı Mantarlı Tavuk',
    'prod_bowl2_kremali_pesto_tavuk': 'Kremalı Pesto Soslu Tavuk',
    'prod_bowl2_izgara_tavuk_gogsu': 'Izgara Tavuk Göğsü',
    'prod_bowl2_izgara_tavuk_pirzola': 'Izgara Tavuk Pirzola',
    'prod_bowl2_citir_tavuk': 'Çıtır Tavuk',
    'prod_bowl2_aci_soslu_dana_bonfile': 'Acı Soslu Dana Bonfile',
    'prod_bowl2_izgara_anne_koftesi': 'Izgara Anne Köftesi',
    'prod_bowl2_izgara_bonfile': 'Izgara Bonfile',
    'prod_bowl2_izgara_somon': 'Izgara Somon',
    'prod_bowl2_somon_fume': 'Somon Füme',
    'prod_bowl2_ton_baligi': 'Ton Balığı',
    'prod_bowl2_falafel': 'Falafel',

    // Tava (cat_tava)
    'prod_tava_citir_tavuk': 'Çıtır Tavuk',
    'prod_tava_tatli_eksi_tavuk': 'Tatlı Ekşi Tavuk',
    'prod_tava_kremali_pestolu_tavuk': 'Kremalı Pestolu Tavuk',
    'prod_tava_kremali_mantarli_tavuk': 'Kremalı Mantarlı Tavuk',
    'prod_tava_izgara_tavuk_gogsu': 'Izgara Tavuk Göğsü',
    'prod_tava_barbeku_soslu_tavuk': 'Barbekü Soslu Tavuk',
    'prod_tava_tatli_aci_tavuk': 'Tatlı Acı Tavuk',
    'prod_tava_izgara_tavuk_pirzola': 'Izgara Tavuk Pirzola',
    'prod_tava_kori_soslu_tavuk': 'Köri Soslu Tavuk',
    'prod_tava_soya_soslu_tavuk': 'Soya Soslu Tavuk',
    'prod_tava_acili_tavuk': 'Acı Soslu Tavuk',
    'prod_tava_kremali_kekikli_tavuk': 'Kremalı Kekikli Tavuk',
    'prod_tava_ton_baligi': 'Ton Balığı',
    'prod_tava_somon_fume': 'Somon Füme',
    'prod_tava_izgara_somon': 'Izgara Somon',
    'prod_tava_anne_koftesi': 'Anne Köftesi',
    'prod_tava_izgara_bonfile': 'Dana Bonfile',
    'prod_tava_acili_bonfile': 'Acılı Bonfile',
    'prod_tava_citir_falafel': 'Çıtır Falafel',

    // Makarna (cat_makarna2)
    'prod_makarna2_citir_tavuk_fettuccine': 'Çıtır Tavuk',
    'prod_makarna2_kofte_fettuccine': 'Köfte',
    'prod_makarna2_dana_bonfile_fettuccine': 'Dana Bonfile',
    'prod_makarna2_fettuccine_chicken_alfredo': 'Tavuk',
    'prod_makarna2_pipette_kofte': 'Izgara Köfte',
    'prod_makarna2_pipette_dana_bonfile': 'Dana Bonfile',
    'prod_makarna2_pipette_citir_tavuk': 'Çıtır Tavuk',
    'prod_makarna2_pipette_izgara_tavuk': 'Izgara Tavuk',
  };

  /// Every Tava plate's recipe is "Mevsim salata, basmati pirinç pilavı,
  /// {protein}" — the two sides are its removable ingredients.
  static const List<String> tava = ['Mevsim Salata', 'Basmati Pirinç Pilavı'];

  static const Map<String, List<String>> byProductId = {
    // Hamburgerler (cat_hamburger2)
    'prod_burger2_double_chicken': [
      'Marul',
      'Cheddar Peyniri',
      'Kornişon Turşu',
      'Ballı Hardal',
    ],
    'prod_burger2_izgara_tavuk': [
      'Marul',
      'Domates',
      'Kornişon Turşu',
      'Cheddar Peyniri',
      'Abaküs Sos',
    ],
    'prod_burger2_falafel': [
      'Marul',
      'Domates',
      'Kornişon Turşu',
      'Yoğurt Sos',
    ],
    'prod_burger2_tripoli': [
      'Cheddar Peyniri',
      'Yumurta',
      'Dana Füme',
      'Sweet Chilli Sos',
    ],
    'prod_burger2_swiss_mushroom': [
      'Cheddar Peyniri',
      'Mantar',
      'Ballı Hardal Sos',
      'Karamelize Soğan',
    ],
    'prod_burger2_steak': [
      'Cheddar Peyniri',
      'Dana Füme',
      'Abaküs Sos',
      'Karamelize Soğan',
    ],
    'prod_burger2_mexico_beef': [
      'Roka',
      'Domates',
      'Kuru Soğan',
      'Jalapeno Turşu',
      'Sweet Chilli Sos',
      'Cheddar Peyniri',
    ],
    'prod_burger2_onion': [
      'Cheddar Peyniri',
      'Abaküs Sos',
      'Karamelize Soğan',
    ],
    'prod_burger2_smoke_house': [
      'Soğan Halkası',
      'Cheddar Peyniri',
      'Dana Füme',
      'Abaküs Sos',
    ],

    // Wrapler (cat_wrap2)
    'prod_wrap2_asian_chicken': [
      'Cheddar Peyniri',
      'Mantar',
      'Kapya Biber',
      'Soya Sos',
    ],
    'prod_wrap2_caesar': [
      'Marul',
      'Roka',
      'Yeşil Elma',
      'Sezar Sos',
      'Parmesan',
    ],
    'prod_wrap2_citir_tavuk': [
      'Marul',
      'Lolorosso',
      'Havuç',
      'Mısır',
      'Cheddar Peyniri',
      'Kornişon Turşu',
      'Ballı Hardal',
    ],
    'prod_wrap2_citir_falafel': [
      'Marul',
      'Havuç',
      'Lolorosso',
      'Beyaz Peynir',
      'Nar',
      'Ceviz',
      'Nar Ekşisi',
      'Tahin',
    ],
    'prod_wrap2_ton_ton': [
      'Marul',
      'Roka',
      'Beyaz Peynir',
      'Zeytin',
      'Çeri Domates',
      'Salatalık',
      'Zeytinyağ',
      'Limon',
      'Nar Ekşisi',
    ],
    'prod_wrap2_kahvalti': [
      'Marul',
      'Havuç',
      'Lolorosso',
      'Beyaz Peynir',
      'Zeytin',
      'Çeri Domates',
      'Avokado',
      'Mısır',
    ],
    'prod_wrap2_kofte': [
      'Marul',
      'Çeri Domates',
      'Kuru Soğan',
      'Abaküs Sos',
    ],
    'prod_wrap2_acili_bonfile': [
      'Roka',
      'Çeri Domates',
      'Mısır',
      'Jalapeno Turşu',
      'Kapya Biber',
      'Sriracha Acı Sos',
    ],
    'prod_wrap2_asian_steak': [
      'Cheddar Peyniri',
      'Mantar',
      'Kapya Biber',
      'Soya Sos',
    ],

    // Makarnalar (cat_makarna2)
    'prod_makarna2_citir_tavuk_fettuccine': ['Kremalı Pesto Sos', 'Parmesan'],
    'prod_makarna2_kofte_fettuccine': ['Kremalı Pesto Sos', 'Parmesan'],
    'prod_makarna2_dana_bonfile_fettuccine': [
      'Kremalı Pesto Sos',
      'Parmesan',
      'Mantar',
    ],
    'prod_makarna2_fettuccine_chicken_alfredo': [
      'Kremalı Pesto Sos',
      'Parmesan',
      'Mantar',
    ],
    'prod_makarna2_pipette_kofte': ['Kremalı Pesto Sos', 'Parmesan'],
    'prod_makarna2_pipette_dana_bonfile': ['Kremalı Pesto Sos', 'Parmesan'],
    'prod_makarna2_pipette_citir_tavuk': ['Kremalı Pesto Sos', 'Parmesan'],
    'prod_makarna2_pipette_izgara_tavuk': ['Kremalı Pesto Sos', 'Parmesan'],

    // Salatalar (cat_salata2)
    'prod_salata2_veggie': [
      'Marul',
      'Havuç',
      'Lolorosso',
      'Mısır',
      'Kapya Biber',
      'Zeytin',
      'Beyaz Peynir',
      'Ceviz',
      'Avokado',
      'Nar',
      'Haşlanmış Yumurta',
      'Zeytinyağ',
      'Limon',
      'Nar Ekşisi',
    ],
    'prod_salata2_grill_caesar': [
      'Marul',
      'Roka',
      'Çeri Domates',
      'Kruton Ekmek',
      'Yeşil Elma',
      'Parmesan Peyniri',
      'Sezar Sos',
    ],
    'prod_salata2_crispy_caesar': [
      'Marul',
      'Roka',
      'Kruton Ekmek',
      'Yeşil Elma',
      'Sezar Sos',
    ],
    'prod_salata2_moms_chicken': [
      'Marul',
      'Yeşil Elma',
      'Makarna',
      'Taze Soğan',
      'Ballı Hardal',
    ],
    'prod_salata2_crispy_falafel': [
      'Marul',
      'Havuç',
      'Lolorosso',
      'Nar',
      'Beyaz Peynir',
      'Ceviz',
      'Nar Ekşisi',
      'Tahin',
    ],
    'prod_salata2_smoked_salmon': [
      'Marul',
      'Lolorosso',
      'Havuç',
      'Çeri Domates',
      'Kapari',
      'Avokado',
      'Ballı Hardal',
    ],
    'prod_salata2_ton_ton': [
      'Marul',
      'Havuç',
      'Lolorosso',
      'Beyaz Peynir',
      'Salatalık',
      'Zeytin',
      'Çeri Domates',
      'Mısır',
      'Zeytinyağ',
      'Limon',
      'Nar Ekşisi',
    ],
    'prod_salata2_ananas': [
      'Marul',
      'Havuç',
      'Lolorosso',
      'Mor Lahana Turşusu',
      'Zeytinyağ',
      'Limon',
      'Nar Ekşisi',
    ],
    'prod_salata2_dana_bonfile': [
      'Roka',
      'Taze Soğan',
      'Makarna',
      'Yeşil Elma',
      'Çeri Domates',
      'Ballı Hardal',
    ],

    // Aperatifler (cat_atistirmalik2) — plain fries / sweet potato have no
    // removable component.
    'prod_aperatif_truflu_patates': ['Trüf Yağı', 'Parmesan', 'Taze Soğan'],
    'prod_aperatif_cheddarli_patates': ['Cheddar Sos', 'Taze Soğan'],
    'prod_aperatif_citir_tavuk': ['Ballı Hardal Sos'],
    'prod_aperatif_citir_falafel': ['Nar Ekşisi', 'Tahin', 'Ceviz'],
    'prod_aperatif_sogan_halkasi': ['Sweet Chilli Sos'],
    'prod_aperatif_general_tso': [
      'Taze Soğan',
      'Çörekotu',
      'Susam',
      'Soya',
    ],
  };
}
