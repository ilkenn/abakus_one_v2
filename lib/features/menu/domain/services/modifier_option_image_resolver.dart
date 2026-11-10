import '../../../bowl_builder/domain/services/ingredient_image_resolver.dart';

/// Maps a subset of `StandardModifierGroups` option ids to the Bowl
/// Builder ingredient photo library (resolved via [IngredientImageResolver]
/// / `ProductImage`), so the POS product customization modal can show a
/// real thumbnail next to an option instead of a generic icon.
///
/// Deliberately partial, and deliberately conservative: an option is only
/// listed here when its name is an exact or trivially grammatical match to
/// an existing ingredient photo's subject (e.g. "Pirinç / Basmati Pilavı"
/// -> `pirinc_pilavi`, "Ekstra Roka Salata" -> the same `roka` photo
/// already used for the plain "Roka" option — it's the same ingredient,
/// just a larger/extra portion). Options with no confident single match —
/// "Kremalı Makarna" (ambiguous among several pasta photos), "Acılı
/// Mayonez"/"Abaküs Sos" (no matching photo at all), every "Patates
/// Tercihi" option (no fries photo exists) — are left out on purpose; the
/// customization modal falls back to [ProductImage]'s own generic
/// placeholder for them rather than guessing.
abstract final class ModifierOptionImageResolver {
  ModifierOptionImageResolver._();

  static const Map<String, String> _ingredientKeyByOptionId = {
    // Karbonhidrat
    'carb_basmati': 'pirinc_pilavi',
    'carb_kuskus': 'kuskus',
    'carb_meksika': 'meksika_pilavi',
    'carb_kremali_pestolu_makarna': 'pesto_makarna',
    'carb_kremali_korili_makarna': 'kori_makarna',
    'carb_kremali_kekikli_makarna': 'kekikli_makarna',
    'carb_bulgur': 'sehriyeli_bulgur_pilavi',
    'carb_kremali_makarna': 'kremali_makarna',
    'carb_kisir': 'kisir',
    'extra_carb_bulgur': 'sehriyeli_bulgur_pilavi',
    'extra_carb_kremali_makarna': 'kremali_makarna',
    'extra_carb_kisir': 'kisir',
    'extra_carb_basmati': 'pirinc_pilavi',
    'extra_carb_meksika': 'meksika_pilavi',
    'extra_carb_kuskus': 'kuskus',
    'extra_carb_kremali_pestolu_makarna': 'pesto_makarna',
    'extra_carb_kremali_korili_makarna': 'kori_makarna',
    'extra_carb_kremali_kekikli_makarna': 'kekikli_makarna',

    // Salata
    'salad_mevsim': 'mevsim_salata',
    'salad_marul': 'marul',
    'salad_roka': 'roka',
    'salad_roka_salata': 'roka_salata',
    'salad_coban': 'coban_salata',
    'extra_salad_marul': 'marul',
    'extra_salad_mevsim': 'mevsim_salata',
    'extra_salad_roka': 'roka',
    'extra_salad_roka_salata': 'roka_salata',
    'extra_salad_coban': 'coban_salata',

    // Sebze (2026-11-09, BR-BOWL-011)
    'veg_standard': 'susamli_corek_otlu_salatalik',
    'veg_mantar_sote': 'mantar_sote',
    'veg_ceri_domates': 'ceri_domates',
    'veg_misir': 'misir',
    'veg_taze_sogan': 'taze_sogan',
    'veg_kuru_sogan': 'kuru_sogan',
    'veg_izgara_kapya': 'izgara_kapya_biber',
    'veg_kapya_biber': 'kapya_biber',
    'veg_izgara_kabak': 'izgara_kabak',
    'veg_yarim_avokado': 'avokado',
    'veg_rende_havuc': 'rende_havuc',
    'veg_izgara_havuc': 'izgara_havuc',
    'veg_meksika_fasulyesi': 'meksika_fasulyesi',
    'veg_izgara_yesil_biber': 'izgara_yesil_biber',
    'veg_yesil_biber': 'yesil_biber',
    'extra_veg_izgara_yesil_biber': 'izgara_yesil_biber',
    'extra_veg_yesil_biber': 'yesil_biber',
    'extra_veg_mantar_sote': 'mantar_sote',
    'extra_veg_ceri_domates': 'ceri_domates',
    'extra_veg_misir': 'misir',
    'extra_veg_taze_sogan': 'taze_sogan',
    'extra_veg_kuru_sogan': 'kuru_sogan',
    'extra_veg_izgara_kapya': 'izgara_kapya_biber',
    'extra_veg_kapya_biber': 'kapya_biber',
    'extra_veg_izgara_kabak': 'izgara_kabak',
    'extra_veg_yarim_avokado': 'avokado',
    'extra_veg_rende_havuc': 'rende_havuc',
    'extra_veg_izgara_havuc': 'izgara_havuc',
    'extra_veg_meksika_fasulyesi': 'meksika_fasulyesi',

    // Meyve (2026-11-09)
    'fruit_yaban_mersini': 'yaban_mersini',
    'fruit_nar': 'nar',
    'fruit_kizarmis_ananas': 'kizarmis_ananas',
    'fruit_frenk_uzumu': 'frenk_uzumu',
    'fruit_kurutulmus_uzum': 'kurutulmus_uzum',

    // Turşu
    'pickle_mor_lahana': 'mor_lahana_tursusu',
    'pickle_kornison': 'kornison_tursu',
    'pickle_jalapeno': 'jalapeno',
    'pickle_kapari': 'kapari',
    'extra_pickle_kapari': 'kapari',
    // Toppings (2026-11-10)
    'topping_siyah_zeytin': 'siyah_zeytin',
    'topping_yesil_zeytin': 'yesil_zeytin',
    'topping_kabak_cekirdegi': 'kabak_cekirdegi',
    'topping_ceviz': 'ceviz',
    'topping_corekotu_susam': 'corekotu_susam',
    'topping_chia': 'chia',
    'topping_keten': 'keten_tohumu',
    'topping_yogurt': 'yogurt',
    'extra_pickle_mor_lahana': 'mor_lahana_tursusu',
    'extra_pickle_kornison': 'kornison_tursu',
    'extra_pickle_jalapeno': 'jalapeno',

    // Sos (universal cross-sell)
    'sauce_mayo': 'mayonez',
    'sauce_balli_hardal': 'balli_hardal',
    'sauce_barbeku': 'barbeku_sos',
    'sauce_sriracha': 'sriracha_sos',
    'sauce_trufflu_mayonez': 'truflu_mayonez',
    'sauce_acili_mayonez': 'acili_mayonez',
    'sauce_abakus': 'abakus_sos',

    // Bowl Sos (2026-11-09)
    'bowl_sauce_zeytinyag_limon': 'zeytinyag_limon_sos',
    'bowl_sauce_yogurt_dipsos': 'yogurt_sos',
    'bowl_sauce_sweet_chilli': 'sweet_chilli',
    'bowl_sauce_nar_eksisi': 'nar_eksisi',
    'bowl_sauce_soya': 'soya_sos',
    'bowl_sauce_sriracha': 'sriracha_sos',
    'bowl_sauce_mayonez': 'mayonez',
    'bowl_sauce_barbeku': 'barbeku_sos',
    'bowl_sauce_hardal': 'hardal_sos',
    'bowl_sauce_balli_hardal': 'balli_hardal',
    'bowl_sauce_uzum_sirkesi': 'uzum_sirkesi',
    'bowl_sauce_sweet_sour': 'sweet_sour',
    'bowl_sauce_tahin': 'tahin',
    'bowl_sauce_ketcap': 'ketcap',
    'bowl_sauce_elma_sirkesi': 'elma_sirkesi',
    'bowl_sauce_acili_mayonez': 'acili_mayonez',
    'bowl_sauce_balsamic': 'balsamic',
    'bowl_sauce_abakus': 'abakus_sos',

    // Ekstra Protein (2026-11-09)
    'protein_addon_tatli_eksi_tavuk': 'tatli_eksi_tavuk',
    'protein_addon_acili_tavuk': 'aci_tavuk',
    'protein_addon_citir_tavuk': 'citir_tavuk',
    'protein_addon_teriyaki_tavuk': 'teriyaki_tavuk',
    'protein_addon_korili_tavuk': 'kori_tavuk',
    'protein_addon_izgara_tavuk_gogus': 'izgara_tavuk',
    'protein_addon_kofte': 'izgara_kofte',
    'protein_addon_dana_bonfile': 'dana_bonfile',
    'protein_addon_ton_baligi': 'ton_baligi',
    'protein_addon_somon_fume': 'somon_fume',
    'protein_addon_falafel': 'falafel',
    'protein_addon_soya_soslu_tavuk': 'soya_tavuk',
    'protein_addon_tatli_aci_tavuk': 'tatli_aci_tavuk',
    'protein_addon_kremali_kekikli_tavuk': 'kremali_kekikli_tavuk',
    'protein_addon_kremali_mantarli_tavuk': 'kremali_mantarli_tavuk',
    'protein_addon_pestolu_tavuk': 'pestolu_tavuk',
    'protein_addon_izgara_tavuk_pirzola': 'izgara_tavuk_pirzola',
    'protein_addon_acili_dana_bonfile': 'acili_dana_bonfile',
    'protein_addon_izgara_somon': 'izgara_somon',
    'protein_addon_izgara_sebze_mix': 'izgara_sebze_mix',

    // Toppings / Peynir (2026-11-09)
    'cheese_beyaz': 'beyaz_peynir',
    'cheese_cheddar': 'cheddar_peyniri',
    'cheese_parmesan': 'parmesan_peyniri',
    'cheese_labne': 'labne',
  };

  /// The Bowl Builder ingredient `imageKey` to resolve for [optionId], or
  /// `null` if no confident match exists.
  static String? imageKeyFor(String optionId) =>
      _ingredientKeyByOptionId[optionId];
}
