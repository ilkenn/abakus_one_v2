import 'brand_asset_set.dart';
import 'brand_color_palette.dart';

/// A partial override of a tenant's base brand theme for one
/// [BrandChannel] — Phase 8 (`docs/decisions.md` ADR-025). Both fields
/// are independently optional: a channel may override only its color
/// palette (e.g. Receipt Branding staying monochrome but using the
/// tenant's accent color) without overriding assets, or vice versa.
/// `null` on either field means "inherit the base theme's value for
/// this," never "blank."
class ChannelBrandingOverride {
  const ChannelBrandingOverride({this.colorPalette, this.assets});

  final BrandColorPalette? colorPalette;
  final BrandAssetSet? assets;
}
