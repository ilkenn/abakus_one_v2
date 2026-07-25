import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/bowl_builder/data/bowl_builder_catalog.dart';
import 'package:abakus_one_v2/features/bowl_builder/domain/models/bowl_builder_step.dart';

void main() {
  const repository = LocalBowlBuilderCatalogRepository();

  test(
    'Bowl Builder 9 kategori + ozet olmak uzere 10 adimdan olusur, dogru sirada',
    () {
      expect(BowlBuilderStep.values.length, 10);
      expect(BowlBuilderStep.values, [
        BowlBuilderStep.protein,
        BowlBuilderStep.carbs,
        BowlBuilderStep.salads,
        BowlBuilderStep.vegetables,
        BowlBuilderStep.fruits,
        BowlBuilderStep.pickles,
        BowlBuilderStep.cheeses,
        BowlBuilderStep.others,
        BowlBuilderStep.sauces,
        BowlBuilderStep.summary,
      ]);
    },
  );

  test(
    'her adimin (ozet haric) .name degeri katalogdaki bir kategori id\'siyle birebir eslesir',
    () {
      final categoryIds = repository.categories.map((c) => c.id).toSet();
      for (final step in BowlBuilderStep.values) {
        if (step == BowlBuilderStep.summary) continue;
        expect(categoryIds.contains(step.name), isTrue,
            reason: '$step icin katalogda eslesen kategori yok');
      }
    },
  );

  test('tam olarak 9 kategori tanimlidir, dogru isimlerle', () {
    expect(repository.categories.length, 9);
    expect(repository.categories.map((c) => c.name).toList(), [
      'Proteinler',
      'Karbonhidratlar',
      'Salatalar',
      'Sebzeler',
      'Meyveler',
      'Turşular',
      'Peynirler',
      'Diğerleri',
      'Soslar',
    ]);
  });

  test(
    'yalnizca Proteinler ve Karbonhidratlar miktar (stepper) destekler',
    () {
      for (final category in repository.categories) {
        final expected =
            category.id == kCategoryProtein || category.id == kCategoryCarbs;
        expect(category.allowsQuantity, expected, reason: category.name);
      }
    },
  );

  test(
    'hicbir malzemenin fiyati 0 veya negatif degildir (ucretsiz/dahil mantigi yok)',
    () {
      for (final category in repository.categories) {
        for (final ingredient in repository.ingredientsFor(category.id)) {
          expect(ingredient.price, greaterThan(0),
              reason: '${category.name} > ${ingredient.name}');
        }
      }
    },
  );

  test('malzeme id\'leri butun katalogda benzersizdir', () {
    final allIds = <String>[];
    for (final category in repository.categories) {
      allIds.addAll(
        repository.ingredientsFor(category.id).map((i) => i.id),
      );
    }
    expect(allIds.length, allIds.toSet().length);
  });

  test('ingredientsFor sortOrder\'a gore sirali doner', () {
    for (final category in repository.categories) {
      final ingredients = repository.ingredientsFor(category.id);
      for (var i = 1; i < ingredients.length; i++) {
        expect(
          ingredients[i].sortOrder,
          greaterThan(ingredients[i - 1].sortOrder),
          reason: category.name,
        );
      }
    }
  });

  test('ingredientById bilinmeyen id icin null doner', () {
    expect(repository.ingredientById('does_not_exist'), isNull);
  });

  test('Meksika Fasulyesi Sebzeler kategorisine tasinmistir', () {
    final ingredient = repository.ingredientById(
      'bb_vegetable_meksika_fasulyesi',
    );
    expect(ingredient, isNotNull);
    expect(ingredient!.categoryId, kCategoryVegetables);
  });

  test('Sebzeler kategorisinde ayrica bir Baklagil kategorisi yoktur', () {
    final categoryIds = repository.categories.map((c) => c.id).toList();
    expect(categoryIds.contains('legumes'), isFalse);
    expect(categoryIds.contains('legume'), isFalse);
  });

  test('daha once gercek olarak verilen protein fiyatlari korunmustur', () {
    final byId = {
      for (final i in repository.ingredientsFor(kCategoryProtein)) i.id: i,
    };
    for (final id in [
      'bb_protein_soya_soslu_tavuk',
      'bb_protein_tatli_eksi_tavuk',
      'bb_protein_kori_soslu_tavuk',
      'bb_protein_tatli_aci_tavuk',
    ]) {
      expect(byId[id]!.price, 40, reason: id);
    }
    expect(byId['bb_protein_izgara_kofte']!.price, 70);
    expect(byId['bb_protein_dana_bonfile']!.price, 150);
    expect(byId['bb_protein_tofu']!.price, 150);
    expect(byId['bb_protein_izgara_somon']!.price, 250);
    expect(byId['bb_protein_somon_fume']!.price, 300);
    expect(byId['bb_protein_ton_baligi']!.price, 150);
  });

  test('daha once gercek olarak verilen diger fiyatlar korunmustur', () {
    expect(repository.ingredientById('bb_carbs_makarna')!.price, 20);
    expect(repository.ingredientById('bb_salad_baby_ispanak')!.price, 30);
    expect(repository.ingredientById('bb_salad_coban_salata')!.price, 30);
    expect(repository.ingredientById('bb_pickle_sogan_tursu')!.price, 20);
    expect(repository.ingredientById('bb_pickle_jalapeno')!.price, 20);
    expect(repository.ingredientById('bb_vegetable_havuc')!.price, 20);
    expect(repository.ingredientById('bb_vegetable_kirmizi_sogan')!.price, 30);
    expect(repository.ingredientById('bb_vegetable_kapya_biber')!.price, 40);
    expect(repository.ingredientById('bb_vegetable_mor_lahana')!.price, 50);
  });
}
