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
    'extra_carb_basmati': 'pirinc_pilavi',
    'extra_carb_meksika': 'meksika_pilavi',

    // Salata
    'salad_mevsim': 'mevsim_salata',
    'salad_marul': 'marul',
    'salad_roka': 'roka',
    'salad_roka_salata': 'roka',
    'salad_coban': 'coban_salata',
    'extra_salad_marul': 'marul',
    'extra_salad_mevsim': 'mevsim_salata',
    'extra_salad_roka': 'roka',
    'extra_salad_coban': 'coban_salata',

    // Turşu
    'pickle_mor_lahana': 'mor_lahana_tursusu',
    'pickle_kornison': 'kornison_tursu',
    'pickle_jalapeno': 'jalapeno',

    // Sos
    'sauce_mayo': 'mayonez',
    'sauce_balli_hardal': 'balli_hardal',
    'sauce_barbeku': 'barbeku_sos',
    'sauce_sriracha': 'sriracha_sos',
    'sauce_trufflu_mayonez': 'truflu_mayonez',

    // İlave Protein (2026-11-03)
    'protein_addon_kofte': 'izgara_kofte',
    'protein_addon_dana_bonfile': 'dana_bonfile',
    'protein_addon_somon_fume': 'somon_fume',
    'protein_addon_falafel': 'falafel',

    // Sos Tercihi (2026-11-03)
    'sauce_choice_balli_hardal': 'balli_hardal',
    'sauce_choice_sweet_chilli': 'sweet_chilli',
    'sauce_choice_sriracha': 'sriracha_sos',

    // Ekstra Topping (2026-11-03)
    'topping_avokado': 'avokado',
    'topping_mantar_sote': 'mantar_sote',
    'topping_parmesan': 'parmesan_peyniri',
  };

  /// The Bowl Builder ingredient `imageKey` to resolve for [optionId], or
  /// `null` if no confident match exists.
  static String? imageKeyFor(String optionId) =>
      _ingredientKeyByOptionId[optionId];
}
