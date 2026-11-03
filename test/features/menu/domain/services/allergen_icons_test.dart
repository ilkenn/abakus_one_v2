import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/menu/domain/services/allergen_icons.dart';

void main() {
  group('AllergenIcons', () {
    test(
        'resolves the exact, product-owner-assigned icon for each of the '
        'five named allergens', () {
      expect(AllergenIcons.iconFor('gluten'), Icons.grain);
      expect(AllergenIcons.iconFor('süt'), Icons.local_drink);
      expect(AllergenIcons.iconFor('susam'), Icons.spa);
      expect(AllergenIcons.iconFor('balık'), Icons.phishing);
      expect(AllergenIcons.iconFor('yumurta'), Icons.egg_outlined);
    });

    test(
        'falls back to a generic icon for an allergen with real data but '
        'no assigned pictogram, never a guessed symbol', () {
      expect(AllergenIcons.iconFor('hardal'), AllergenIcons.fallbackIcon);
      expect(AllergenIcons.iconFor('soya'), AllergenIcons.fallbackIcon);
      expect(AllergenIcons.iconFor('ceviz'), AllergenIcons.fallbackIcon);
    });

    test('falls back to the generic icon for an unknown allergen string', () {
      expect(AllergenIcons.iconFor('not_a_real_allergen'),
          AllergenIcons.fallbackIcon);
    });
  });
}
