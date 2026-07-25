import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/bowl_builder/data/bowl_builder_catalog.dart';
import 'package:abakus_one_v2/features/bowl_builder/domain/models/bowl_layer_type.dart';

void main() {
  test('render sirasi degismez: base -> topping', () {
    expect(BowlLayerType.values, [
      BowlLayerType.base,
      BowlLayerType.protein,
      BowlLayerType.vegetable,
      BowlLayerType.cheese,
      BowlLayerType.sauce,
      BowlLayerType.topping,
    ]);
  });

  test('kataloktaki 9 kategorinin hepsi bir katmana eslenir', () {
    expect(BowlLayerType.forCategoryId(kCategoryCarbs), BowlLayerType.base);
    expect(
      BowlLayerType.forCategoryId(kCategoryProtein),
      BowlLayerType.protein,
    );
    expect(
      BowlLayerType.forCategoryId(kCategorySalads),
      BowlLayerType.vegetable,
    );
    expect(
      BowlLayerType.forCategoryId(kCategoryVegetables),
      BowlLayerType.vegetable,
    );
    expect(
      BowlLayerType.forCategoryId(kCategoryFruits),
      BowlLayerType.vegetable,
    );
    expect(
      BowlLayerType.forCategoryId(kCategoryPickles),
      BowlLayerType.vegetable,
    );
    expect(
      BowlLayerType.forCategoryId(kCategoryCheeses),
      BowlLayerType.cheese,
    );
    expect(BowlLayerType.forCategoryId(kCategorySauces), BowlLayerType.sauce);
    expect(
      BowlLayerType.forCategoryId(kCategoryOthers),
      BowlLayerType.topping,
    );
  });

  test('bilinmeyen bir kategori id icin hata firlatir (sessizce yutmaz)', () {
    expect(
      () => BowlLayerType.forCategoryId('bilinmeyen-kategori'),
      throwsArgumentError,
    );
  });

  test(
    'katalogdaki her kategori gercekten forCategoryId ile cozumlenebilir '
    '(regresyon: yeni kategori eklenince burada da eklenmeli)',
    () {
      const repository = LocalBowlBuilderCatalogRepository();
      for (final category in repository.categories) {
        expect(
          () => BowlLayerType.forCategoryId(category.id),
          returnsNormally,
          reason: category.name,
        );
      }
    },
  );
}
