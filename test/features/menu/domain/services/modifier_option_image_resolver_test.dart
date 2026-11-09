import 'package:flutter_test/flutter_test.dart';
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

    test(
        'returns null for a 2026-11-09 option with no confident match '
        '(no "somon"/"tahin"/"walnut"/"labne" photo exists)', () {
      expect(
          ModifierOptionImageResolver.imageKeyFor('protein_addon_izgara_somon'),
          isNull);
      expect(
          ModifierOptionImageResolver.imageKeyFor('bowl_sauce_tahin'), isNull);
      expect(ModifierOptionImageResolver.imageKeyFor('topping_ceviz'), isNull);
      expect(ModifierOptionImageResolver.imageKeyFor('cheese_labne'), isNull);
    });

    test('returns null for an option with no confident match, never a guess',
        () {
      expect(ModifierOptionImageResolver.imageKeyFor('carb_kremali_makarna'),
          isNull);
      expect(ModifierOptionImageResolver.imageKeyFor('sauce_abakus'), isNull);
      expect(ModifierOptionImageResolver.imageKeyFor('fries_spicy'), isNull);
    });

    test('returns null for an unknown option id', () {
      expect(
          ModifierOptionImageResolver.imageKeyFor('not_a_real_option'), isNull);
    });
  });
}
