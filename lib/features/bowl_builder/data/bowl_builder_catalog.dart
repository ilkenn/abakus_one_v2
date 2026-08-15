import '../domain/models/bowl_builder_category.dart';
import '../domain/models/bowl_builder_ingredient.dart';

// Category ids — each matches the corresponding `BowlBuilderStep` enum
// value's `.name` exactly (see that file's doc comment).
const String kCategoryProtein = 'protein';
const String kCategoryCarbs = 'carbs';
const String kCategorySalads = 'salads';
const String kCategoryVegetables = 'vegetables';
const String kCategoryFruits = 'fruits';
const String kCategoryPickles = 'pickles';
const String kCategoryCheeses = 'cheeses';
const String kCategoryOthers = 'others';
const String kCategorySauces = 'sauces';

/// Single source of truth for Bowl Builder's categories and ingredient
/// prices. UI, `BowlBuilderNotifier`, and every pricing provider read only
/// through [BowlBuilderCatalogRepository] — none of them knows whether the
/// data behind it is [LocalBowlBuilderCatalogRepository]'s compiled-in list
/// or a later admin-configured/remote source. Swapping that in is a change
/// to `bowlBuilderCatalogRepositoryProvider`'s implementation alone —
/// exactly the same pattern already used by `ordersRepositoryProvider`
/// (`orders_provider.dart`) and `authRepositoryProvider` (`auth_provider.dart`).
///
/// Changing one ingredient's price is a one-line edit to this file; no UI,
/// provider, or cart code ever needs to change alongside it. The same is
/// true of `imageKey` — see `IngredientImageResolver`.
abstract interface class BowlBuilderCatalogRepository {
  List<BowlBuilderCategory> get categories;

  /// [categoryId]'s ingredients, in [BowlBuilderIngredient.sortOrder] order.
  List<BowlBuilderIngredient> ingredientsFor(String categoryId);

  /// The ingredient with this id, or `null` if it doesn't exist in the
  /// catalog (e.g. removed after a customer already selected it).
  BowlBuilderIngredient? ingredientById(String id);
}

/// Today's only implementation — a compiled-in constant list.
///
/// **Every price below is a PLACEHOLDER** (product decision, 2026-07-23:
/// real per-ingredient pricing wasn't available yet, so the feature is built
/// against illustrative numbers rather than blocking on it). Where a real
/// price already existed from an earlier phase of this catalog (protein
/// tiers, Makarna, Baby Ispanak/Çoban Salata, Soğan Turşusu/Jalapeño,
/// vegetable tiers, every "Diğerleri" item), that real number is kept
/// unchanged; every other ingredient gets a small, clearly-illustrative
/// round number. Replacing these with real prices is the same one-line-per-
/// ingredient edit as any other price change here.
///
/// **Every `caloriesKcal`/`proteinGrams`/`fatGrams`/`carbohydrateGrams`
/// value below is ALSO A DEVELOPMENT PLACEHOLDER** (v2 live-nutrition-
/// dashboard redesign, 2026-08-08). No real nutrition data source exists
/// for this catalog yet — these are rough, illustrative, per-selected-
/// portion estimates typed in to demonstrate the live nutrition dashboard
/// UI, **not** sourced from any nutrition database or verified against real
/// recipe yields. Do not present them to a customer as accurate. Replacing
/// them with real, kitchen-verified values is the same one-line-per-
/// ingredient edit as any other field here — no UI, provider, or cart code
/// needs to change alongside it.
///
/// Every `imageKey` below is the ingredient's own name, slugified to match
/// [IngredientImageResolver]'s registry (Faz 8.1, 2026-07-24: real photos
/// landed under `assets/images/products/`). Most now resolve to a real
/// photo; a minority don't yet (the photo batch didn't cover them, or its
/// filename doesn't match closely enough to trust an automatic guess) and
/// correctly fall back to [ProductImage]'s placeholder — see that
/// resolver's doc for the exact list and the process to fill one in.
class LocalBowlBuilderCatalogRepository
    implements BowlBuilderCatalogRepository {
  const LocalBowlBuilderCatalogRepository();

  @override
  List<BowlBuilderCategory> get categories => _categories;

  @override
  List<BowlBuilderIngredient> ingredientsFor(String categoryId) {
    final result =
        _ingredients.where((i) => i.categoryId == categoryId).toList();
    result.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return result;
  }

  @override
  BowlBuilderIngredient? ingredientById(String id) {
    for (final ingredient in _ingredients) {
      if (ingredient.id == id) return ingredient;
    }
    return null;
  }
}

const List<BowlBuilderCategory> _categories = [
  BowlBuilderCategory(
    id: kCategoryProtein,
    name: 'Proteinler',
    allowsQuantity: true,
  ),
  BowlBuilderCategory(
    id: kCategoryCarbs,
    name: 'Karbonhidratlar',
    allowsQuantity: true,
  ),
  BowlBuilderCategory(id: kCategorySalads, name: 'Salatalar'),
  BowlBuilderCategory(id: kCategoryVegetables, name: 'Sebzeler'),
  BowlBuilderCategory(id: kCategoryFruits, name: 'Meyveler'),
  BowlBuilderCategory(id: kCategoryPickles, name: 'Turşular'),
  BowlBuilderCategory(id: kCategoryCheeses, name: 'Peynirler'),
  // Customer-facing label is "Ekstralar" (v2 redesign) — id/name stay
  // 'others'/'Diğerleri' everywhere else in the system; see
  // BowlBuilderCategory.displayName's doc comment.
  BowlBuilderCategory(
    id: kCategoryOthers,
    name: 'Diğerleri',
    displayName: 'Ekstralar',
  ),
  BowlBuilderCategory(id: kCategorySauces, name: 'Soslar'),
];

const List<BowlBuilderIngredient> _ingredients = [
  // ---- Proteinler — istenildiği kadar eklenebilir (stepper). ----
  BowlBuilderIngredient(
    id: 'bb_protein_izgara_tavuk',
    name: 'Izgara Tavuk',
    categoryId: kCategoryProtein,
    price: 40,
    imageKey: 'izgara_tavuk',
    sortOrder: 0,
    caloriesKcal: 165,
    proteinGrams: 31,
    fatGrams: 4,
    carbohydrateGrams: 0,
  ),
  BowlBuilderIngredient(
    id: 'bb_protein_citir_tavuk',
    name: 'Çıtır Tavuk',
    categoryId: kCategoryProtein,
    price: 40,
    imageKey: 'citir_tavuk',
    sortOrder: 1,
    caloriesKcal: 220,
    proteinGrams: 24,
    fatGrams: 11,
    carbohydrateGrams: 8,
  ),
  BowlBuilderIngredient(
    id: 'bb_protein_falafel',
    name: 'Falafel',
    categoryId: kCategoryProtein,
    price: 35,
    imageKey: 'falafel',
    sortOrder: 2,
    caloriesKcal: 180,
    proteinGrams: 8,
    fatGrams: 10,
    carbohydrateGrams: 17,
  ),
  BowlBuilderIngredient(
    id: 'bb_protein_soya_soslu_tavuk',
    name: 'Soya Soslu Tavuk',
    categoryId: kCategoryProtein,
    price: 40,
    imageKey: 'soya_tavuk',
    sortOrder: 3,
    caloriesKcal: 190,
    proteinGrams: 28,
    fatGrams: 6,
    carbohydrateGrams: 5,
  ),
  BowlBuilderIngredient(
    id: 'bb_protein_tatli_eksi_tavuk',
    name: 'Tatlı Ekşi Tavuk',
    categoryId: kCategoryProtein,
    price: 40,
    imageKey: 'tatli_eksi_tavuk',
    sortOrder: 4,
    caloriesKcal: 210,
    proteinGrams: 26,
    fatGrams: 6,
    carbohydrateGrams: 12,
  ),
  BowlBuilderIngredient(
    id: 'bb_protein_kori_soslu_tavuk',
    name: 'Köri Soslu Tavuk',
    categoryId: kCategoryProtein,
    price: 40,
    imageKey: 'kori_tavuk',
    sortOrder: 5,
    caloriesKcal: 195,
    proteinGrams: 27,
    fatGrams: 7,
    carbohydrateGrams: 6,
  ),
  BowlBuilderIngredient(
    id: 'bb_protein_tatli_aci_tavuk',
    name: 'Tatlı Acı Tavuk',
    categoryId: kCategoryProtein,
    price: 40,
    imageKey: 'aci_tavuk',
    sortOrder: 6,
    caloriesKcal: 200,
    proteinGrams: 26,
    fatGrams: 6,
    carbohydrateGrams: 10,
  ),
  BowlBuilderIngredient(
    id: 'bb_protein_izgara_kofte',
    name: 'Izgara Köfte',
    categoryId: kCategoryProtein,
    price: 70,
    imageKey: 'izgara_kofte',
    sortOrder: 7,
    caloriesKcal: 250,
    proteinGrams: 22,
    fatGrams: 17,
    carbohydrateGrams: 2,
  ),
  BowlBuilderIngredient(
    id: 'bb_protein_dana_bonfile',
    name: 'Dana Bonfile',
    categoryId: kCategoryProtein,
    price: 150,
    imageKey: 'dana_bonfile',
    sortOrder: 8,
    caloriesKcal: 240,
    proteinGrams: 30,
    fatGrams: 12,
    carbohydrateGrams: 0,
  ),
  BowlBuilderIngredient(
    id: 'bb_protein_tofu',
    name: 'Tofu',
    categoryId: kCategoryProtein,
    price: 150,
    imageKey: 'tofu',
    sortOrder: 9,
    caloriesKcal: 120,
    proteinGrams: 12,
    fatGrams: 7,
    carbohydrateGrams: 3,
  ),
  BowlBuilderIngredient(
    id: 'bb_protein_izgara_somon',
    name: 'Izgara Somon',
    categoryId: kCategoryProtein,
    price: 250,
    imageKey: 'izgara_somon',
    sortOrder: 10,
    caloriesKcal: 280,
    proteinGrams: 28,
    fatGrams: 18,
    carbohydrateGrams: 0,
  ),
  BowlBuilderIngredient(
    id: 'bb_protein_somon_fume',
    name: 'Somon Füme',
    categoryId: kCategoryProtein,
    price: 300,
    imageKey: 'somon_fume',
    sortOrder: 11,
    caloriesKcal: 200,
    proteinGrams: 25,
    fatGrams: 10,
    carbohydrateGrams: 0,
  ),
  BowlBuilderIngredient(
    id: 'bb_protein_ton_baligi',
    name: 'Ton Balığı',
    categoryId: kCategoryProtein,
    price: 150,
    imageKey: 'ton_baligi',
    sortOrder: 12,
    caloriesKcal: 150,
    proteinGrams: 30,
    fatGrams: 3,
    carbohydrateGrams: 0,
  ),

  // ---- Karbonhidratlar — istenildiği kadar eklenebilir (stepper). ----
  BowlBuilderIngredient(
    id: 'bb_carbs_meksika_pilavi',
    name: 'Meksika Pilavı',
    categoryId: kCategoryCarbs,
    price: 15,
    imageKey: 'meksika_pilavi',
    sortOrder: 0,
    caloriesKcal: 190,
    proteinGrams: 4,
    fatGrams: 4,
    carbohydrateGrams: 34,
  ),
  BowlBuilderIngredient(
    id: 'bb_carbs_beyaz_basmati',
    name: 'Beyaz Basmati Pirinç',
    categoryId: kCategoryCarbs,
    price: 15,
    imageKey: 'beyaz_basmati_pirinc',
    sortOrder: 1,
    caloriesKcal: 180,
    proteinGrams: 3,
    fatGrams: 0,
    carbohydrateGrams: 40,
  ),
  BowlBuilderIngredient(
    id: 'bb_carbs_siyah_basmati',
    name: 'Siyah Basmati Pirinç',
    categoryId: kCategoryCarbs,
    price: 15,
    imageKey: 'siyah_basmati_pirinc',
    sortOrder: 2,
    caloriesKcal: 170,
    proteinGrams: 4,
    fatGrams: 1,
    carbohydrateGrams: 35,
  ),
  BowlBuilderIngredient(
    id: 'bb_carbs_karisik_basmati',
    name: 'Beyaz + Siyah Basmati Karışımı',
    categoryId: kCategoryCarbs,
    price: 15,
    imageKey: 'beyaz_siyah_basmati_karisimi',
    sortOrder: 3,
    caloriesKcal: 175,
    proteinGrams: 4,
    fatGrams: 1,
    carbohydrateGrams: 37,
  ),
  BowlBuilderIngredient(
    id: 'bb_carbs_meyhane_pilavi',
    name: 'Meyhane Pilavı',
    categoryId: kCategoryCarbs,
    price: 15,
    imageKey: 'meyhane_pilavi',
    sortOrder: 4,
    caloriesKcal: 195,
    proteinGrams: 4,
    fatGrams: 5,
    carbohydrateGrams: 33,
  ),
  BowlBuilderIngredient(
    id: 'bb_carbs_kinoa',
    name: 'Kinoa',
    categoryId: kCategoryCarbs,
    price: 20,
    imageKey: 'kinoa',
    sortOrder: 5,
    caloriesKcal: 180,
    proteinGrams: 6,
    fatGrams: 3,
    carbohydrateGrams: 32,
  ),
  BowlBuilderIngredient(
    id: 'bb_carbs_bulgur_pilavi',
    name: 'Bulgur Pilavı',
    categoryId: kCategoryCarbs,
    price: 15,
    imageKey: 'bulgur_pilavi',
    sortOrder: 6,
    caloriesKcal: 170,
    proteinGrams: 5,
    fatGrams: 2,
    carbohydrateGrams: 34,
  ),
  BowlBuilderIngredient(
    id: 'bb_carbs_kuskus',
    name: 'Kuskus',
    categoryId: kCategoryCarbs,
    price: 15,
    imageKey: 'kuskus',
    sortOrder: 7,
    caloriesKcal: 175,
    proteinGrams: 5,
    fatGrams: 1,
    carbohydrateGrams: 36,
  ),
  BowlBuilderIngredient(
    id: 'bb_carbs_makarna',
    name: 'Makarna',
    categoryId: kCategoryCarbs,
    price: 20,
    imageKey: 'makarna',
    sortOrder: 8,
    caloriesKcal: 200,
    proteinGrams: 7,
    fatGrams: 1,
    carbohydrateGrams: 40,
  ),

  // ---- Salatalar — bir porsiyon, tekrar tıklanınca kaldırılır. ----
  BowlBuilderIngredient(
    id: 'bb_salad_mevsim',
    name: 'Mevsim Salata',
    categoryId: kCategorySalads,
    price: 15,
    imageKey: 'mevsim_salata',
    sortOrder: 0,
    caloriesKcal: 20,
    proteinGrams: 1,
    fatGrams: 0,
    carbohydrateGrams: 4,
  ),
  BowlBuilderIngredient(
    id: 'bb_salad_kivircik_marul',
    name: 'Kıvırcık Marul',
    categoryId: kCategorySalads,
    price: 15,
    imageKey: 'kivircik_marul',
    sortOrder: 1,
    caloriesKcal: 10,
    proteinGrams: 1,
    fatGrams: 0,
    carbohydrateGrams: 2,
  ),
  BowlBuilderIngredient(
    id: 'bb_salad_roka',
    name: 'Roka',
    categoryId: kCategorySalads,
    price: 15,
    imageKey: 'roka',
    sortOrder: 2,
    caloriesKcal: 12,
    proteinGrams: 1,
    fatGrams: 0,
    carbohydrateGrams: 2,
  ),
  BowlBuilderIngredient(
    id: 'bb_salad_baby_ispanak',
    name: 'Baby Ispanak',
    categoryId: kCategorySalads,
    price: 30,
    imageKey: 'baby_ispanak',
    sortOrder: 3,
    caloriesKcal: 15,
    proteinGrams: 2,
    fatGrams: 0,
    carbohydrateGrams: 2,
  ),
  BowlBuilderIngredient(
    id: 'bb_salad_coban_salata',
    name: 'Çoban Salata',
    categoryId: kCategorySalads,
    price: 30,
    imageKey: 'coban_salata',
    sortOrder: 4,
    caloriesKcal: 30,
    proteinGrams: 1,
    fatGrams: 1,
    carbohydrateGrams: 5,
  ),

  // ---- Sebzeler — bir porsiyon, tekrar tıklanınca kaldırılır. ----
  // Meksika Fasulyesi eskiden ayrı "Baklagil" kategorisindeydi; yeni 9
  // kategoride ayrı bir baklagil kategorisi olmadığı için buraya taşındı
  // (product decision, 2026-07-23).
  BowlBuilderIngredient(
    id: 'bb_vegetable_misir',
    name: 'Mısır',
    categoryId: kCategoryVegetables,
    price: 10,
    imageKey: 'misir',
    sortOrder: 0,
    caloriesKcal: 35,
    proteinGrams: 1,
    fatGrams: 0,
    carbohydrateGrams: 8,
  ),
  BowlBuilderIngredient(
    id: 'bb_vegetable_salatalik',
    name: 'Salatalık',
    categoryId: kCategoryVegetables,
    price: 10,
    imageKey: 'salatalik',
    sortOrder: 1,
    caloriesKcal: 8,
    proteinGrams: 0,
    fatGrams: 0,
    carbohydrateGrams: 2,
  ),
  BowlBuilderIngredient(
    id: 'bb_vegetable_domates',
    name: 'Domates',
    categoryId: kCategoryVegetables,
    price: 10,
    imageKey: 'domates',
    sortOrder: 2,
    caloriesKcal: 10,
    proteinGrams: 0,
    fatGrams: 0,
    carbohydrateGrams: 2,
  ),
  BowlBuilderIngredient(
    id: 'bb_vegetable_havuc',
    name: 'Havuç',
    categoryId: kCategoryVegetables,
    price: 20,
    imageKey: 'izgara_havuc',
    sortOrder: 3,
    caloriesKcal: 20,
    proteinGrams: 0,
    fatGrams: 0,
    carbohydrateGrams: 5,
  ),
  BowlBuilderIngredient(
    id: 'bb_vegetable_kirmizi_sogan',
    name: 'Kırmızı Soğan',
    categoryId: kCategoryVegetables,
    price: 30,
    imageKey: 'kirmizi_sogan',
    sortOrder: 4,
    caloriesKcal: 15,
    proteinGrams: 0,
    fatGrams: 0,
    carbohydrateGrams: 4,
  ),
  BowlBuilderIngredient(
    id: 'bb_vegetable_kapya_biber',
    name: 'Kapya Biber',
    categoryId: kCategoryVegetables,
    price: 40,
    imageKey: 'kapya_biber',
    sortOrder: 5,
    caloriesKcal: 15,
    proteinGrams: 1,
    fatGrams: 0,
    carbohydrateGrams: 3,
  ),
  BowlBuilderIngredient(
    id: 'bb_vegetable_mor_lahana',
    name: 'Mor Lahana',
    categoryId: kCategoryVegetables,
    price: 50,
    imageKey: 'mor_lahana',
    sortOrder: 6,
    caloriesKcal: 12,
    proteinGrams: 1,
    fatGrams: 0,
    carbohydrateGrams: 3,
  ),
  BowlBuilderIngredient(
    id: 'bb_vegetable_meksika_fasulyesi',
    name: 'Meksika Fasulyesi',
    categoryId: kCategoryVegetables,
    price: 15,
    imageKey: 'meksika_fasulyesi',
    sortOrder: 7,
    caloriesKcal: 60,
    proteinGrams: 4,
    fatGrams: 0,
    carbohydrateGrams: 11,
  ),

  // ---- Meyveler — bir porsiyon, tekrar tıklanınca kaldırılır. ----
  BowlBuilderIngredient(
    id: 'bb_fruit_ananas',
    name: 'Ananas',
    categoryId: kCategoryFruits,
    price: 15,
    imageKey: 'ananas',
    sortOrder: 0,
    caloriesKcal: 30,
    proteinGrams: 0,
    fatGrams: 0,
    carbohydrateGrams: 8,
  ),
  BowlBuilderIngredient(
    id: 'bb_fruit_yesil_elma',
    name: 'Yeşil Elma',
    categoryId: kCategoryFruits,
    price: 15,
    imageKey: 'yesil_elma',
    sortOrder: 1,
    caloriesKcal: 26,
    proteinGrams: 0,
    fatGrams: 0,
    carbohydrateGrams: 7,
  ),
  BowlBuilderIngredient(
    id: 'bb_fruit_nar',
    name: 'Nar',
    categoryId: kCategoryFruits,
    price: 20,
    imageKey: 'nar',
    sortOrder: 2,
    caloriesKcal: 40,
    proteinGrams: 1,
    fatGrams: 0,
    carbohydrateGrams: 9,
  ),
  BowlBuilderIngredient(
    id: 'bb_fruit_muz',
    name: 'Muz',
    categoryId: kCategoryFruits,
    price: 15,
    imageKey: 'muz',
    sortOrder: 3,
    caloriesKcal: 45,
    proteinGrams: 1,
    fatGrams: 0,
    carbohydrateGrams: 11,
  ),
  BowlBuilderIngredient(
    id: 'bb_fruit_ahududu',
    name: 'Ahududu',
    categoryId: kCategoryFruits,
    price: 20,
    imageKey: 'ahududu',
    sortOrder: 4,
    caloriesKcal: 26,
    proteinGrams: 1,
    fatGrams: 0,
    carbohydrateGrams: 6,
  ),
  BowlBuilderIngredient(
    id: 'bb_fruit_bogurtlen',
    name: 'Böğürtlen',
    categoryId: kCategoryFruits,
    price: 20,
    imageKey: 'bogurtlen',
    sortOrder: 5,
    caloriesKcal: 22,
    proteinGrams: 1,
    fatGrams: 0,
    carbohydrateGrams: 5,
  ),

  // ---- Turşular — bir porsiyon, tekrar tıklanınca kaldırılır. ----
  BowlBuilderIngredient(
    id: 'bb_pickle_mor_lahana',
    name: 'Mor Lahana Turşusu',
    categoryId: kCategoryPickles,
    price: 10,
    imageKey: 'mor_lahana_tursusu',
    sortOrder: 0,
    caloriesKcal: 10,
    proteinGrams: 0,
    fatGrams: 0,
    carbohydrateGrams: 2,
  ),
  BowlBuilderIngredient(
    id: 'bb_pickle_kornison',
    name: 'Kornişon Turşu',
    categoryId: kCategoryPickles,
    price: 10,
    imageKey: 'kornison_tursu',
    sortOrder: 1,
    caloriesKcal: 8,
    proteinGrams: 0,
    fatGrams: 0,
    carbohydrateGrams: 2,
  ),
  BowlBuilderIngredient(
    id: 'bb_pickle_sogan_tursu',
    name: 'Soğan Turşusu',
    categoryId: kCategoryPickles,
    price: 20,
    imageKey: 'sogan_tursusu',
    sortOrder: 2,
    caloriesKcal: 12,
    proteinGrams: 0,
    fatGrams: 0,
    carbohydrateGrams: 3,
  ),
  BowlBuilderIngredient(
    id: 'bb_pickle_jalapeno',
    name: 'Jalapeño',
    categoryId: kCategoryPickles,
    price: 20,
    imageKey: 'jalapeno',
    sortOrder: 3,
    caloriesKcal: 8,
    proteinGrams: 0,
    fatGrams: 0,
    carbohydrateGrams: 2,
  ),

  // ---- Peynirler — bir porsiyon, tekrar tıklanınca kaldırılır. ----
  BowlBuilderIngredient(
    id: 'bb_cheese_beyaz',
    name: 'Beyaz Peynir',
    categoryId: kCategoryCheeses,
    price: 15,
    imageKey: 'beyaz_peynir',
    sortOrder: 0,
    caloriesKcal: 80,
    proteinGrams: 5,
    fatGrams: 6,
    carbohydrateGrams: 1,
  ),
  BowlBuilderIngredient(
    id: 'bb_cheese_cheddar',
    name: 'Cheddar Peyniri',
    categoryId: kCategoryCheeses,
    price: 15,
    imageKey: 'cheddar_peyniri',
    sortOrder: 1,
    caloriesKcal: 110,
    proteinGrams: 7,
    fatGrams: 9,
    carbohydrateGrams: 1,
  ),
  BowlBuilderIngredient(
    id: 'bb_cheese_parmesan',
    name: 'Parmesan Peyniri',
    categoryId: kCategoryCheeses,
    price: 20,
    imageKey: 'parmesan_peyniri',
    sortOrder: 2,
    caloriesKcal: 120,
    proteinGrams: 10,
    fatGrams: 8,
    carbohydrateGrams: 1,
  ),
  BowlBuilderIngredient(
    id: 'bb_cheese_labne',
    name: 'Labne',
    categoryId: kCategoryCheeses,
    price: 15,
    imageKey: 'labne',
    sortOrder: 3,
    caloriesKcal: 60,
    proteinGrams: 3,
    fatGrams: 5,
    carbohydrateGrams: 2,
  ),

  // ---- Diğerleri (Toppingler / "Ekstralar") — bir porsiyon, tekrar
  // tıklanınca kaldırılır. ----
  BowlBuilderIngredient(
    id: 'bb_other_avokado',
    name: 'Avokado',
    categoryId: kCategoryOthers,
    price: 25,
    imageKey: 'avokado',
    sortOrder: 0,
    caloriesKcal: 80,
    proteinGrams: 1,
    fatGrams: 7,
    carbohydrateGrams: 4,
  ),
  BowlBuilderIngredient(
    id: 'bb_other_zeytin',
    name: 'Zeytin',
    categoryId: kCategoryOthers,
    price: 10,
    imageKey: 'zeytin',
    sortOrder: 1,
    caloriesKcal: 40,
    proteinGrams: 0,
    fatGrams: 4,
    carbohydrateGrams: 1,
  ),
  BowlBuilderIngredient(
    id: 'bb_other_ceviz',
    name: 'Ceviz',
    categoryId: kCategoryOthers,
    price: 15,
    imageKey: 'ceviz',
    sortOrder: 2,
    caloriesKcal: 130,
    proteinGrams: 3,
    fatGrams: 13,
    carbohydrateGrams: 2,
  ),
  BowlBuilderIngredient(
    id: 'bb_other_kabak_cekirdegi',
    name: 'Kabak Çekirdeği',
    categoryId: kCategoryOthers,
    price: 10,
    imageKey: 'kabak_cekirdegi',
    sortOrder: 3,
    caloriesKcal: 90,
    proteinGrams: 5,
    fatGrams: 8,
    carbohydrateGrams: 2,
  ),
  BowlBuilderIngredient(
    id: 'bb_other_sote_mantar',
    name: 'Sote Mantar',
    categoryId: kCategoryOthers,
    price: 15,
    imageKey: 'mantar_sote',
    sortOrder: 4,
    caloriesKcal: 25,
    proteinGrams: 2,
    fatGrams: 1,
    carbohydrateGrams: 2,
  ),

  // ---- Soslar — bir porsiyon, tekrar tıklanınca kaldırılır. ----
  BowlBuilderIngredient(
    id: 'bb_sauce_zeytinyag_limon',
    name: 'Zeytinyağ Limon Sos',
    categoryId: kCategorySauces,
    price: 10,
    imageKey: 'zeytinyag_limon_sos',
    sortOrder: 0,
    caloriesKcal: 90,
    proteinGrams: 0,
    fatGrams: 10,
    carbohydrateGrams: 0,
  ),
  BowlBuilderIngredient(
    id: 'bb_sauce_nar_eksisi',
    name: 'Nar Ekşisi',
    categoryId: kCategorySauces,
    price: 10,
    imageKey: 'nar_eksisi',
    sortOrder: 1,
    caloriesKcal: 30,
    proteinGrams: 0,
    fatGrams: 0,
    carbohydrateGrams: 7,
  ),
  BowlBuilderIngredient(
    id: 'bb_sauce_yogurt',
    name: 'Yoğurt Sos',
    categoryId: kCategorySauces,
    price: 10,
    imageKey: 'yogurt_sos',
    sortOrder: 2,
    caloriesKcal: 25,
    proteinGrams: 1,
    fatGrams: 2,
    carbohydrateGrams: 1,
  ),
  BowlBuilderIngredient(
    id: 'bb_sauce_balli_hardal',
    name: 'Ballı Hardal',
    categoryId: kCategorySauces,
    price: 10,
    imageKey: 'balli_hardal',
    sortOrder: 3,
    caloriesKcal: 40,
    proteinGrams: 0,
    fatGrams: 2,
    carbohydrateGrams: 6,
  ),
  BowlBuilderIngredient(
    id: 'bb_sauce_aci_sos',
    name: 'Acı Sos',
    categoryId: kCategorySauces,
    price: 10,
    imageKey: 'aci_sos',
    sortOrder: 4,
    caloriesKcal: 10,
    proteinGrams: 0,
    fatGrams: 0,
    carbohydrateGrams: 2,
  ),
  BowlBuilderIngredient(
    id: 'bb_sauce_caesar',
    name: 'Caesar Sos',
    categoryId: kCategorySauces,
    price: 10,
    imageKey: 'caesar_sos',
    sortOrder: 5,
    caloriesKcal: 80,
    proteinGrams: 1,
    fatGrams: 8,
    carbohydrateGrams: 1,
  ),
  BowlBuilderIngredient(
    id: 'bb_sauce_soya',
    name: 'Soya Sos',
    categoryId: kCategorySauces,
    price: 10,
    imageKey: 'soya_sos',
    sortOrder: 6,
    caloriesKcal: 10,
    proteinGrams: 1,
    fatGrams: 0,
    carbohydrateGrams: 1,
  ),
  BowlBuilderIngredient(
    id: 'bb_sauce_pesto',
    name: 'Pesto Sos',
    categoryId: kCategorySauces,
    price: 10,
    imageKey: 'pesto_sos',
    sortOrder: 7,
    caloriesKcal: 90,
    proteinGrams: 1,
    fatGrams: 9,
    carbohydrateGrams: 1,
  ),
  BowlBuilderIngredient(
    id: 'bb_sauce_tahin',
    name: 'Tahin',
    categoryId: kCategorySauces,
    price: 10,
    imageKey: 'tahin',
    sortOrder: 8,
    caloriesKcal: 90,
    proteinGrams: 3,
    fatGrams: 8,
    carbohydrateGrams: 3,
  ),
  BowlBuilderIngredient(
    id: 'bb_sauce_abakus',
    name: 'Abaküs Sos',
    categoryId: kCategorySauces,
    price: 10,
    imageKey: 'abakus_sos',
    sortOrder: 9,
    caloriesKcal: 70,
    proteinGrams: 1,
    fatGrams: 6,
    carbohydrateGrams: 3,
  ),
];
