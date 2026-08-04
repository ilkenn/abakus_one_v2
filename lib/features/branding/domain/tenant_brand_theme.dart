import 'brand_asset_set.dart';
import 'brand_channel.dart';
import 'brand_color_palette.dart';
import 'brand_typography.dart';
import 'channel_branding_override.dart';

/// A tenant's complete brand identity — Phase 8 (`docs/decisions.md`
/// ADR-025), the domain root of the kickoff's own hierarchy: "Tenant →
/// Brand → Theme → Application Identity → Logo → Colors → Typography →
/// Splash → Icons → Favicon → [6 channel-specific brandings]."
///
/// Scoped to `organizationId` (the tenant boundary this codebase
/// already established — `docs/decisions.md` ADR-023 Decision 3), not
/// `restaurantId` — `Restaurant`'s own doc comment already calls it "a
/// brand under an Organization," but branding has a different mutation
/// cadence and a different actor (tenant owner, not restaurant
/// operational staff) than `Restaurant`'s own operational fields, so it
/// is kept as its own aggregate rather than added to `Restaurant`
/// directly — the same reasoning `PosOrderSession`/`OrderClosure` were
/// each kept separate from `Order` (ADR-011/ADR-012).
///
/// Mutable, revision-tracked (mirrors `Restaurant`/`Branch`, not an
/// append-only financial record) — branding evolves in place; every
/// change is still recorded via `BrandingAuditEntry`.
class TenantBrandTheme {
  const TenantBrandTheme({
    required this.id,
    required this.organizationId,
    required this.brandDisplayName,
    required this.colorPalette,
    required this.typography,
    this.assets = const BrandAssetSet(),
    this.channelOverrides = const {},
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;

  /// The tenant's brand name as shown to their own customers — never
  /// the technical `Organization.name`/project identifier, mirroring
  /// this codebase's own "Abaküs only, never `abakus_one_v2`" rule
  /// (`CLAUDE.md` §1) applied per-tenant instead of hardcoded once.
  final String brandDisplayName;

  final BrandColorPalette colorPalette;
  final BrandTypography typography;
  final BrandAssetSet assets;
  final Map<BrandChannel, ChannelBrandingOverride> channelOverrides;
  final DateTime createdAt;
  final int revision;

  TenantBrandTheme copyWith({
    String? brandDisplayName,
    BrandColorPalette? colorPalette,
    BrandTypography? typography,
    BrandAssetSet? assets,
    Map<BrandChannel, ChannelBrandingOverride>? channelOverrides,
    required int revision,
  }) {
    return TenantBrandTheme(
      id: id,
      organizationId: organizationId,
      brandDisplayName: brandDisplayName ?? this.brandDisplayName,
      colorPalette: colorPalette ?? this.colorPalette,
      typography: typography ?? this.typography,
      assets: assets ?? this.assets,
      channelOverrides: channelOverrides ?? this.channelOverrides,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
