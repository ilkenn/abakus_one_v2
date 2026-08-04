import 'package:flutter/material.dart';

import '../domain/resolve_effective_brand_theme.dart';

/// Applies an [EffectiveBrandPresentation]'s color palette on top of a
/// base `ThemeData` — Phase 8 (`docs/decisions.md` ADR-025).
///
/// **Deliberately narrow scope**: this overrides only the top-level
/// `ColorScheme` (`primary`/`secondary`/`tertiary`), which every
/// built-in Material widget and any `Theme.of(context).colorScheme`
/// read already consults automatically — it does **not** touch
/// [base]'s typography, shapes, or any other `ThemeData` field, and it
/// never touches `AppColors`/`AppTheme`'s own static definitions
/// (`core/theme/*` remains "the working example" `CLAUDE.md` §6 calls
/// it — this builds an override layer *above* it, never edits it).
/// Individual screens that read `AppColors.primary`/etc. directly
/// (rather than through `Theme.of(context)`) do **not** pick up a
/// tenant's brand color from this — sweeping every screen onto
/// theme-driven color reads is separate, larger, unapproved work,
/// honestly disclosed here rather than silently claimed complete.
///
/// A palette failing [BrandColorPalette.isValid] is never applied —
/// [base] is returned unchanged rather than risk building a `ThemeData`
/// from a malformed color.
ThemeData buildThemeFromBrandPresentation({
  required ThemeData base,
  required EffectiveBrandPresentation presentation,
}) {
  if (!presentation.colorPalette.isValid) return base;

  final primary = _parseHexColor(presentation.colorPalette.primaryColorHex);
  final secondary = _parseHexColor(presentation.colorPalette.secondaryColorHex);
  final accent = _parseHexColor(presentation.colorPalette.accentColorHex);
  if (primary == null || secondary == null || accent == null) return base;

  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: primary,
      secondary: secondary,
      tertiary: accent,
    ),
  );
}

/// `#RRGGBB` or `#AARRGGBB` → [Color]. Returns `null` for anything not
/// already validated by [BrandColorPalette.isValid] — never throws.
Color? _parseHexColor(String hex) {
  final stripped = hex.replaceFirst('#', '');
  final normalized = stripped.length == 6 ? 'FF$stripped' : stripped;
  final value = int.tryParse(normalized, radix: 16);
  if (value == null) return null;
  return Color(value);
}
