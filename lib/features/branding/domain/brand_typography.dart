/// A tenant's chosen typography — Phase 8 (`docs/decisions.md`
/// ADR-025). [fontFamilyName] must name a font family this app already
/// bundles or the platform provides — dynamically downloading/loading
/// an arbitrary font file per tenant is explicitly out of scope for
/// this foundation ("do not implement publishing" applies equally to
/// "do not implement dynamic asset delivery"). Validating a submitted
/// name against the app's actual bundled font catalog is Phase 8F's
/// (or a later phase's) presentation-layer concern, not this domain
/// type's.
class BrandTypography {
  const BrandTypography({required this.fontFamilyName});

  final String fontFamilyName;
}
