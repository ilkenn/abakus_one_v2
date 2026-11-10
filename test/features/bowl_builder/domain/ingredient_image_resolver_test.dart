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
      // 2026-11-10: Tofu removed from the catalog and its photo deleted.
      expect(IngredientImageResolver.resolve('tofu'), isNull);
      expect(IngredientImageResolver.resolve('citir_tofu'), isNull);
      // "Tavuk sote" icin hic foto yok (2026-11-10: labne/ceviz artik var).
      expect(IngredientImageResolver.resolve('tavuk_sote'), isNull);
    },
  );

  test(
    'katalogdaki eslesmeyen malzeme sayisi bilinen ve sabit kalir '
    '(regresyon: yeni foto eklenince bu sayi dusmeli, artmamali)',
    () {
      final missing = IngredientImageResolver.findMissingImageKeys(
        allImageKeys(),
      );
      // 2026-11-10: 21 -> 19 after the sauce photo batch.
      // 19 -> 17 after the protein/cheese batch.
      // 17 -> 15 after the veg/pickle/topping batch.
      // 15 -> 1 after removing 14 ingredients (owner request); 1 -> 0 once
      // Tofu was removed too — every Bowl Builder ingredient has a photo.
      expect(missing.length, 0, reason: missing.join(', '));
    },
  );

  test(
    'kullanilmayan (orphan) foto sayisi bilinen ve sabit kalir '
    '(regresyon: katalog genisleyince bu sayi dusmeli)',
    () {
      final orphaned = IngredientImageResolver.findOrphanedImageKeys(
        allImageKeys(),
      );
      // 2026-11-10: 35 -> 41 — the new sauce photos (balsamic, elma_sirkesi,
      // sweet_sour, uzum_sirkesi, acili_mayonez, abakus_sos) are used by
      // product modifier options, not by the Bowl Builder catalog.
      // 41 -> 46 — roka_salata, kisir, kremali_makarna, frenk_uzumu and
      // kurutulmus_uzum are product-modifier photos, not Bowl Builder ones.
      // 46 -> 53 — 7 protein/cheese photos used only by product modifiers.
      // 53 -> 62 — topping/pepper/kapari photos used only by product modifiers.
      // 62 -> 61 — citir_tofu.png deleted with Tofu.
      expect(orphaned.length, 61, reason: orphaned.join(', '));
    },
  );
}
