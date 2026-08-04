/// A tenant's chosen color palette — Phase 8 (`docs/decisions.md`
/// ADR-025). Stored as data (hex strings), never as compiled Dart
/// `Color` constants — the entire point of a white-label brand engine
/// is that a color is a tenant's *configuration*, not this codebase's
/// design-token source. `AppColors` (the design-system default,
/// `CLAUDE.md` §6) remains what renders when no `TenantBrandTheme`
/// applies; parsing a hex string into a real `Color` happens only at
/// the presentation layer (Phase 8F), never here.
class BrandColorPalette {
  const BrandColorPalette({
    required this.primaryColorHex,
    required this.secondaryColorHex,
    required this.accentColorHex,
  });

  /// `#RRGGBB` or `#AARRGGBB`, always including the leading `#` — never
  /// a bare Flutter `Color(0x...)` int, so this stays serializable data
  /// a future backend/admin form can round-trip without any Dart-side
  /// parsing assumption baked in.
  final String primaryColorHex;
  final String secondaryColorHex;
  final String accentColorHex;

  static final _hexPattern = RegExp(r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

  bool get isValid =>
      _hexPattern.hasMatch(primaryColorHex) &&
      _hexPattern.hasMatch(secondaryColorHex) &&
      _hexPattern.hasMatch(accentColorHex);
}
