import 'package:abakus_one_v2/features/branding/domain/brand_color_palette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrandColorPalette.isValid', () {
    test('accepts valid 6-digit hex colors', () {
      const palette = BrandColorPalette(
        primaryColorHex: '#FF5733',
        secondaryColorHex: '#33FF57',
        accentColorHex: '#3357FF',
      );

      expect(palette.isValid, isTrue);
    });

    test('accepts valid 8-digit (alpha) hex colors', () {
      const palette = BrandColorPalette(
        primaryColorHex: '#FFFF5733',
        secondaryColorHex: '#FF33FF57',
        accentColorHex: '#FF3357FF',
      );

      expect(palette.isValid, isTrue);
    });

    test('rejects a color missing the leading #', () {
      const palette = BrandColorPalette(
        primaryColorHex: 'FF5733',
        secondaryColorHex: '#33FF57',
        accentColorHex: '#3357FF',
      );

      expect(palette.isValid, isFalse);
    });

    test('rejects a color with an invalid length', () {
      const palette = BrandColorPalette(
        primaryColorHex: '#FFF',
        secondaryColorHex: '#33FF57',
        accentColorHex: '#3357FF',
      );

      expect(palette.isValid, isFalse);
    });

    test('rejects a color with non-hex characters', () {
      const palette = BrandColorPalette(
        primaryColorHex: '#GGGGGG',
        secondaryColorHex: '#33FF57',
        accentColorHex: '#3357FF',
      );

      expect(palette.isValid, isFalse);
    });
  });
}
