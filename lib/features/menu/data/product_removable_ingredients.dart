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
/// or falafel/egg base, e.g. "150 gr. Çıtır Tavuk") is deliberately left
/// out: dropping it would no longer be the product that was ordered.
abstract final class ProductRemovableIngredients {
  ProductRemovableIngredients._();

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
