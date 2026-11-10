import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/bowl_builder/domain/services/ingredient_image_resolver.dart';
import 'package:abakus_one_v2/features/menu/data/standard_modifier_groups.dart';
import 'package:abakus_one_v2/features/menu/domain/services/modifier_option_image_resolver.dart';

void main() {
  group('ModifierOptionImageResolver', () {
    test('resolves a confident exact-name match', () {
      expect(ModifierOptionImageResolver.imageKeyFor('carb_basmati'),
          'pirinc_pilavi');
      expect(ModifierOptionImageResolver.imageKeyFor('salad_mevsim'),
          'mevsim_salata');
      expect(ModifierOptionImageResolver.imageKeyFor('pickle_kornison'),
          'kornison_tursu');
      expect(ModifierOptionImageResolver.imageKeyFor('sauce_balli_hardal'),
          'balli_hardal');
    });

    test('an "Ekstra X" option reuses the same base ingredient photo', () {
      expect(ModifierOptionImageResolver.imageKeyFor('extra_salad_roka'),
          ModifierOptionImageResolver.imageKeyFor('salad_roka'));
    });

    test(
        'resolves a confident match for the 2026-11-09 PDF Bowl groups '
        '(protein/sebze/meyve/peynir/sos)', () {
      expect(ModifierOptionImageResolver.imageKeyFor('protein_addon_kofte'),
          'izgara_kofte');
      expect(
          ModifierOptionImageResolver.imageKeyFor('protein_addon_dana_bonfile'),
          'dana_bonfile');
      expect(ModifierOptionImageResolver.imageKeyFor('veg_mantar_sote'),
          'mantar_sote');
      expect(ModifierOptionImageResolver.imageKeyFor('fruit_nar'), 'nar');
      expect(ModifierOptionImageResolver.imageKeyFor('cheese_parmesan'),
          'parmesan_peyniri');
      expect(ModifierOptionImageResolver.imageKeyFor('bowl_sauce_sweet_chilli'),
          'sweet_chilli');
    });

    test('returns null for an option with no confident match, never a guess',
        () {
      expect(ModifierOptionImageResolver.imageKeyFor('fries_spicy'), isNull);
    });

    // 2026-11-10 — every option in these fully-photographed groups has a
    // photo, and that photo really exists on disk.
    test(
        'every sauce / salad / carb / fruit / cheese / protein / veg / pickle / topping option resolves to an existing '
        'asset file', () {
      final options = [
        ...StandardModifierGroups.bowlSauceGroup.options,
        ...StandardModifierGroups.crossSellSauceGroup.options,
        ...StandardModifierGroups.bowlSaladGroup.options,
        ...StandardModifierGroups.bowlExtraSaladGroup.options,
        ...StandardModifierGroups.bowlCarbGroup.options,
        ...StandardModifierGroups.bowlExtraCarbGroup.options,
        ...StandardModifierGroups.bowlFruitGroup.options,
        ...StandardModifierGroups.bowlCheeseGroup.options,
        ...StandardModifierGroups.bowlExtraProteinGroup.options,
        ...StandardModifierGroups.bowlVegetableGroup.options,
        ...StandardModifierGroups.bowlExtraVegetableGroup.options,
        ...StandardModifierGroups.bowlPickleGroup.options,
        ...StandardModifierGroups.bowlExtraPickleGroup.options,
        ...StandardModifierGroups.bowlToppingsGroup.options,
      ];
      for (final option in options) {
        final key = ModifierOptionImageResolver.imageKeyFor(option.id);
        expect(key, isNotNull, reason: '${option.id} has no image key');
        final path = IngredientImageResolver.resolve(key!);
        expect(path, isNotNull, reason: '${option.id} -> $key has no path');
        expect(File(path!).existsSync(), isTrue,
            reason: '${option.id} -> $path is missing');
      }
    });

    test('Abaküs Sos shares the Acılı Mayonez photo', () {
      expect(
        IngredientImageResolver.resolve(
            ModifierOptionImageResolver.imageKeyFor('sauce_abakus')!),
        IngredientImageResolver.resolve(
            ModifierOptionImageResolver.imageKeyFor('sauce_acili_mayonez')!),
      );
    });

    test('returns null for an unknown option id', () {
      expect(
          ModifierOptionImageResolver.imageKeyFor('not_a_real_option'), isNull);
    });
  });
}
