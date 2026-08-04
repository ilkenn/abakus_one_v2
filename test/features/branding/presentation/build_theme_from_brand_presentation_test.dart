import 'package:abakus_one_v2/features/branding/domain/brand_asset_set.dart';
import 'package:abakus_one_v2/features/branding/domain/brand_color_palette.dart';
import 'package:abakus_one_v2/features/branding/domain/resolve_effective_brand_theme.dart';
import 'package:abakus_one_v2/features/branding/presentation/build_theme_from_brand_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildThemeFromBrandPresentation', () {
    test('applies the palette onto the base ColorScheme', () {
      final base = ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Colors.blue,
          secondary: Colors.green,
          tertiary: Colors.orange,
        ),
      );
      const presentation = EffectiveBrandPresentation(
        colorPalette: BrandColorPalette(
          primaryColorHex: '#FF0000',
          secondaryColorHex: '#00FF00',
          accentColorHex: '#0000FF',
        ),
        assets: BrandAssetSet(),
      );

      final result = buildThemeFromBrandPresentation(
        base: base,
        presentation: presentation,
      );

      expect(result.colorScheme.primary, const Color(0xFFFF0000));
      expect(result.colorScheme.secondary, const Color(0xFF00FF00));
      expect(result.colorScheme.tertiary, const Color(0xFF0000FF));
    });

    test('leaves non-color fields of the base theme untouched', () {
      final base = ThemeData(useMaterial3: true);
      const presentation = EffectiveBrandPresentation(
        colorPalette: BrandColorPalette(
          primaryColorHex: '#FF0000',
          secondaryColorHex: '#00FF00',
          accentColorHex: '#0000FF',
        ),
        assets: BrandAssetSet(),
      );

      final result = buildThemeFromBrandPresentation(
        base: base,
        presentation: presentation,
      );

      expect(result.useMaterial3, base.useMaterial3);
    });

    test('an invalid palette leaves the base theme unchanged', () {
      final base = ThemeData(
        colorScheme: const ColorScheme.light(primary: Colors.blue),
      );
      const presentation = EffectiveBrandPresentation(
        colorPalette: BrandColorPalette(
          primaryColorHex: 'not-a-color',
          secondaryColorHex: '#00FF00',
          accentColorHex: '#0000FF',
        ),
        assets: BrandAssetSet(),
      );

      final result = buildThemeFromBrandPresentation(
        base: base,
        presentation: presentation,
      );

      expect(result.colorScheme.primary, Colors.blue);
    });

    test('supports 8-digit (alpha-prefixed) hex colors', () {
      final base = ThemeData(
        colorScheme: const ColorScheme.light(primary: Colors.blue),
      );
      const presentation = EffectiveBrandPresentation(
        colorPalette: BrandColorPalette(
          primaryColorHex: '#80FF0000',
          secondaryColorHex: '#00FF00',
          accentColorHex: '#0000FF',
        ),
        assets: BrandAssetSet(),
      );

      final result = buildThemeFromBrandPresentation(
        base: base,
        presentation: presentation,
      );

      expect(result.colorScheme.primary, const Color(0x80FF0000));
    });
  });
}
