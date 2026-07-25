import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/bowl_builder/data/bowl_builder_catalog.dart';
import 'package:abakus_one_v2/features/bowl_builder/domain/services/ingredient_image_resolver.dart';

void main() {
  const repository = LocalBowlBuilderCatalogRepository();

  List<String> allImageKeys() => [
        for (final category in repository.categories)
          for (final ingredient in repository.ingredientsFor(category.id))
            ingredient.imageKey!,
      ];

  test(
    'katalogdaki her malzemenin gercek, bos-olmayan bir imageKey degeri var '
    '(gorseller eklenmeye hazir)',
    () {
      for (final category in repository.categories) {
        for (final ingredient in repository.ingredientsFor(category.id)) {
          expect(
            ingredient.imageKey,
            isNotNull,
            reason: '${category.name} > ${ingredient.name}',
          );
          expect(ingredient.imageKey, isNotEmpty);
        }
      }
    },
  );

  test('bilinmeyen bir anahtar icin null doner', () {
    expect(IngredientImageResolver.resolve('hic-boyle-bir-sey-yok'), isNull);
  });

  test(
    'gercek foto eklenmis olan ornek malzemeler dogru asset yoluna cozumlenir',
    () {
      expect(
        IngredientImageResolver.resolve('izgara_tavuk'),
        'assets/images/products/Proteinler/izgara_tavuk.png',
      );
      expect(
        IngredientImageResolver.resolve('domates'),
        'assets/images/products/Sebzeler/domates.png',
      );
      expect(
        IngredientImageResolver.resolve('zeytinyag_limon_sos'),
        'assets/images/products/Soslar/zeytinyag_limon_sos.png',
      );
      // Fiziksel klasoru kendi kategorisiyle eslesmeyen ama ayni isimli
      // gercek bir fotografi olan bir "Diğerleri" malzemesi: Avokado'nun
      // fotografi Sebzeler klasorunde, ama isim eslesmesi yeterli.
      expect(
        IngredientImageResolver.resolve('avokado'),
        'assets/images/products/Sebzeler/avokado.png',
      );
    },
  );

  test(
    'urun onayli 6 eslestirme (Faz 8.1.1, 2026-07-24) dogru PNGye cozumlenir',
    () {
      final byId = {
        for (final category in repository.categories)
          for (final ingredient in repository.ingredientsFor(category.id))
            ingredient.id: ingredient,
      };

      final expected = {
        'bb_protein_soya_soslu_tavuk': 'Proteinler/soya_tavuk.png',
        'bb_protein_kori_soslu_tavuk': 'Proteinler/kori_tavuk.png',
        'bb_protein_tatli_aci_tavuk': 'Proteinler/aci_tavuk.png',
        'bb_other_sote_mantar': 'Sebzeler/mantar_sote.png',
        'bb_vegetable_havuc': 'Sebzeler/izgara_havuc.png',
        'bb_pickle_jalapeno': 'Turşular/jalepeno_tursusu.png',
      };

      for (final entry in expected.entries) {
        final ingredient = byId[entry.key]!;
        expect(
          IngredientImageResolver.resolve(ingredient.imageKey!),
          'assets/images/products/${entry.value}',
          reason: ingredient.name,
        );
      }
    },
  );

  test(
    'henuz fotografi olmayan malzikeler icin resolve null doner (placeholder gosterilir)',
    () {
      // "Tofu" icin sadece "citir_tofu.png" var, duz "tofu.png" yok.
      expect(IngredientImageResolver.resolve('tofu'), isNull);
      // "Labne" icin hic foto yok.
      expect(IngredientImageResolver.resolve('labne'), isNull);
    },
  );

  test(
    'katalogdaki eslesmeyen malzeme sayisi bilinen ve sabit kalir '
    '(regresyon: yeni foto eklenince bu sayi dusmeli, artmamali)',
    () {
      final missing = IngredientImageResolver.findMissingImageKeys(
        allImageKeys(),
      );
      expect(missing.length, 21, reason: missing.join(', '));
    },
  );

  test(
    'kullanilmayan (orphan) foto sayisi bilinen ve sabit kalir '
    '(regresyon: katalog genisleyince bu sayi dusmeli)',
    () {
      final orphaned = IngredientImageResolver.findOrphanedImageKeys(
        allImageKeys(),
      );
      expect(orphaned.length, 35, reason: orphaned.join(', '));
    },
  );
}
