import 'brand_asset_set.dart';
import 'brand_channel.dart';
import 'brand_color_palette.dart';
import 'tenant_brand_theme.dart';

/// The fully-resolved brand presentation for one [BrandChannel] — every
/// field always populated (never partially `null` the way
/// `ChannelBrandingOverride` is), because a consumer rendering a
/// specific channel should never have to fall back to the base theme
/// itself field-by-field.
class EffectiveBrandPresentation {
  const EffectiveBrandPresentation({
    required this.colorPalette,
    required this.assets,
  });

  final BrandColorPalette colorPalette;
  final BrandAssetSet assets;
}

/// A pure, synchronous computation — no I/O, mirrors `RecipeLineFlattener`/
/// `NutritionAggregator`'s "pure domain service over already-resolved
/// data" shape (Phase 7, `docs/decisions.md` ADR-024) — resolving the
/// effective presentation for a channel by layering that channel's
/// `ChannelBrandingOverride` (if any) on top of the tenant's base
/// `TenantBrandTheme`. A channel with no override, or one that only
/// overrides one of `colorPalette`/`assets`, resolves the rest from the
/// base theme untouched.
class ResolveEffectiveBrandTheme {
  const ResolveEffectiveBrandTheme();

  EffectiveBrandPresentation call({
    required TenantBrandTheme theme,
    required BrandChannel channel,
  }) {
    final override = theme.channelOverrides[channel];
    return EffectiveBrandPresentation(
      colorPalette: override?.colorPalette ?? theme.colorPalette,
      assets: override?.assets ?? theme.assets,
    );
  }
}
