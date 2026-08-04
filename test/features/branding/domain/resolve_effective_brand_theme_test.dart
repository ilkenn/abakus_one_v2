import 'package:abakus_one_v2/features/branding/domain/brand_asset_set.dart';
import 'package:abakus_one_v2/features/branding/domain/brand_channel.dart';
import 'package:abakus_one_v2/features/branding/domain/brand_color_palette.dart';
import 'package:abakus_one_v2/features/branding/domain/brand_typography.dart';
import 'package:abakus_one_v2/features/branding/domain/channel_branding_override.dart';
import 'package:abakus_one_v2/features/branding/domain/resolve_effective_brand_theme.dart';
import 'package:abakus_one_v2/features/branding/domain/tenant_brand_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseColorPalette = BrandColorPalette(
    primaryColorHex: '#111111',
    secondaryColorHex: '#222222',
    accentColorHex: '#333333',
  );
  const baseAssets =
      BrandAssetSet(logoRef: 'base-logo', splashRef: 'base-splash');

  TenantBrandTheme buildTheme({
    Map<BrandChannel, ChannelBrandingOverride> channelOverrides = const {},
  }) {
    return TenantBrandTheme(
      id: 'theme-1',
      organizationId: 'org-1',
      brandDisplayName: 'Test Brand',
      colorPalette: baseColorPalette,
      typography: const BrandTypography(fontFamilyName: 'Inter'),
      assets: baseAssets,
      channelOverrides: channelOverrides,
      createdAt: DateTime(2026, 1, 1),
      revision: 1,
    );
  }

  group('ResolveEffectiveBrandTheme', () {
    test('a channel with no override resolves to the base theme unchanged', () {
      final theme = buildTheme();
      const resolver = ResolveEffectiveBrandTheme();

      final result = resolver(theme: theme, channel: BrandChannel.receipt);

      expect(result.colorPalette, baseColorPalette);
      expect(result.assets, baseAssets);
    });

    test('a channel overriding only colorPalette keeps the base assets', () {
      const overrideColors = BrandColorPalette(
        primaryColorHex: '#AAAAAA',
        secondaryColorHex: '#BBBBBB',
        accentColorHex: '#CCCCCC',
      );
      final theme = buildTheme(channelOverrides: {
        BrandChannel.receipt:
            const ChannelBrandingOverride(colorPalette: overrideColors),
      });
      const resolver = ResolveEffectiveBrandTheme();

      final result = resolver(theme: theme, channel: BrandChannel.receipt);

      expect(result.colorPalette, overrideColors);
      expect(result.assets, baseAssets);
    });

    test('a channel overriding only assets keeps the base colorPalette', () {
      const overrideAssets = BrandAssetSet(logoRef: 'receipt-logo');
      final theme = buildTheme(channelOverrides: {
        BrandChannel.receipt:
            const ChannelBrandingOverride(assets: overrideAssets),
      });
      const resolver = ResolveEffectiveBrandTheme();

      final result = resolver(theme: theme, channel: BrandChannel.receipt);

      expect(result.colorPalette, baseColorPalette);
      expect(result.assets, overrideAssets);
    });

    test('overriding one channel never affects a different channel', () {
      const overrideColors = BrandColorPalette(
        primaryColorHex: '#AAAAAA',
        secondaryColorHex: '#BBBBBB',
        accentColorHex: '#CCCCCC',
      );
      final theme = buildTheme(channelOverrides: {
        BrandChannel.receipt:
            const ChannelBrandingOverride(colorPalette: overrideColors),
      });
      const resolver = ResolveEffectiveBrandTheme();

      final result = resolver(theme: theme, channel: BrandChannel.push);

      expect(result.colorPalette, baseColorPalette);
    });
  });
}
