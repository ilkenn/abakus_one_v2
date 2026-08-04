/// A tenant's brand image assets — Phase 8 (`docs/decisions.md`
/// ADR-025). Every field is a fully opaque reference string, never raw
/// image bytes — the exact same "media bytes must not be stored in
/// this codebase" boundary Phase 6's `CustomerPhoto.photoRef` already
/// established (`docs/decisions.md` ADR-023 Decision 5). No
/// `image_picker`/cloud-storage dependency exists in this codebase;
/// resolving a ref into an actual displayable image is a future,
/// separately-approved integration.
class BrandAssetSet {
  const BrandAssetSet({
    this.logoRef,
    this.splashRef,
    this.iconRef,
    this.faviconRef,
  });

  final String? logoRef;
  final String? splashRef;
  final String? iconRef;

  /// Web only — `AppColors`/`AppTheme` and the rest of this app have no
  /// web-specific asset concept today; this field exists for the
  /// "Favicon" leaf of the kickoff's own branding hierarchy, unused
  /// until a web build target actually renders one.
  final String? faviconRef;

  bool get isEmpty =>
      logoRef == null &&
      splashRef == null &&
      iconRef == null &&
      faviconRef == null;
}
