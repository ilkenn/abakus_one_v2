import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// **Deliberate, approved exception to the single-shared-design-system
/// rule** (CLAUDE.md §6, `docs/admin_pos_architecture.md` §19) — scoped
/// *only* to the customer-facing QR ordering flow ("Warm Artisanal &
/// Craft" visual direction), per explicit product-owner direction dated
/// 2026-10-29.
///
/// `lib/core/theme/app_colors.dart`/`app_typography.dart` (and everything
/// else under `core/theme/`) remain the sole, unmodified visual authority
/// for POS, Admin, and every other surface — this file is never imported
/// by `lib/features/pos/**`, `lib/features/admin/**`, or
/// `lib/features/platform/**`. It exists so the customer ordering screens
/// (Menu, Product Detail, Home's product surfaces, Active Order Tracking)
/// can diverge visually without that divergence leaking into POS/Admin, and
/// without silently repurposing the shared `AppColors`/`AppTypography`
/// tokens other surfaces still depend on.
///
/// **Dark mode**: no dark variant exists yet for this scoped theme, same
/// caveat as the global `AppTheme` — every color below is chosen so it
/// could plausibly map onto a dark surface later (e.g. [primary]/
/// [primaryDeep] already read as "dark surface" tones), but that mapping
/// is not built here.
///
/// **Contrast — Verified, not assumed** (computed against the WCAG 2.2
/// relative-luminance formula, the same rigor this project's Splash
/// tagline fix established as the standing bar):
/// - [background] (#FAF7F2) vs [primary] (#1B3B2B): **11.51:1** — safe for
///   any body text size.
/// - [background] vs [textSecondary] (#5B6B61): **5.28:1** — safe for
///   normal-size body text (≥4.5:1 required).
/// - [background] vs [gold] (#D4AF37): **1.97:1** — FAILS even large-text
///   contrast. [gold]/[goldMuted] must never be used as a text/icon color
///   directly on [background] — only as a fill/accent on a dark surface
///   (see below) or as a purely decorative stroke/border.
/// - [background] vs [terracotta] (#C85A32): **3.96:1** — passes the
///   large-text/UI-component floor (≥3:1) but fails normal body text
///   (≥4.5:1). Reserve [terracotta] text/icons on [background] for large,
///   bold, short labels (badges, headings) — never small body copy.
/// - [primary] vs white: **12.30:1** — white text/icons on a [primary] or
///   [primaryDeep] fill is always safe.
/// - [primary] vs [gold]: **5.85:1**, [primary] vs [goldMuted]: **5.01:1**
///   — both safe for normal text/icons *when gold sits on a dark [primary]
///   surface*, which is the only context this theme uses gold for text.
/// - [terracotta] vs white: **4.23:1** — just under the normal-text floor;
///   restrict white-on-terracotta to large/bold short labels (≥3:1
///   context), not paragraph copy.
abstract final class QrMenuColors {
  QrMenuColors._();

  static const Color background = Color(0xFFFAF7F2);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color primary = Color(0xFF1B3B2B);
  static const Color primaryDeep = Color(0xFF1E3329);

  static const Color gold = Color(0xFFD4AF37);
  static const Color goldMuted = Color(0xFFC5A059);
  static const Color terracotta = Color(0xFFC85A32);

  static const Color textPrimary = primary;
  static const Color textSecondary = Color(0xFF5B6B61);
  static const Color onPrimary = Color(0xFFFFFFFF);

  static const Color border = Color(0xFFE7DFD2);

  /// Backing tint for a frosted/glassmorphism badge (see `GlassCard`) —
  /// high-opacity on purpose: the badge sits over variable food photography,
  /// not a flat token-defined background, so it leans on near-opaque tint +
  /// blur (rather than a thin frost) to keep [onPrimary] text legible
  /// regardless of what photo is underneath, approximating the verified
  /// [primary]-vs-white 12.30:1 pair above.
  static const Color glassBadgeTint = Color(0xCC1B3B2B); // primary @ ~80%
}

/// Type roles for the QR ordering flow — Plus Jakarta Sans for
/// display/headline/title (the brief's premium/editorial voice), Inter for
/// body/caption (readability at small sizes), Outfit for short badge/label
/// text. Loaded via `google_fonts` (pinned `^6.2.1`, user-approved
/// 2026-10-29 — see `pubspec.yaml`'s own comment). The global
/// `AppTypography` stays on the platform default font, unchanged.
abstract final class QrMenuTypography {
  QrMenuTypography._();

  static TextStyle get display => GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: QrMenuColors.textPrimary,
        letterSpacing: -0.5,
      );

  static TextStyle get headline => GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: QrMenuColors.textPrimary,
      );

  static TextStyle get title => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: QrMenuColors.textPrimary,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: QrMenuColors.textPrimary,
        height: 1.4,
      );

  static TextStyle get bodySecondary => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: QrMenuColors.textSecondary,
        height: 1.3,
      );

  static TextStyle get caption => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: QrMenuColors.textSecondary,
        letterSpacing: 0.4,
      );

  /// Short, bold badge/chip text (price pills, "Yeni"/dietary tags) — sized
  /// for a compact glass badge, always paired with a token-verified-safe
  /// foreground (see [QrMenuColors]'s contrast log), never gold/terracotta
  /// directly on [QrMenuColors.background].
  static TextStyle get badge => GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: QrMenuColors.onPrimary,
      );
}

/// The resolved color set for one moment in time — [QrMenuAmbientTint]
/// is the only thing that produces one.
@immutable
class QrMenuAmbientPalette {
  final Color background;
  final Color primary;
  final Color accent;

  const QrMenuAmbientPalette({
    required this.background,
    required this.primary,
    required this.accent,
  });

  @override
  bool operator ==(Object other) =>
      other is QrMenuAmbientPalette &&
      other.background == background &&
      other.primary == primary &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(background, primary, accent);
}

/// "Ambient auto-tint" — after local 18:00 the QR ordering screens shift
/// warmer/darker (dim cream background, deepen sage, warm the gold accent
/// toward terracotta). A **pure function of an hour**, deliberately not a
/// widget calling `DateTime.now()` inline: callers resolve the current hour
/// once (see `qrMenuAmbientPaletteProvider`), so this is unit-testable in
/// isolation and never recomputed mid-rebuild.
abstract final class QrMenuAmbientTint {
  QrMenuAmbientTint._();

  /// Evening window starts at 18:00 and runs through the early hours
  /// (before 05:00) — matches a restaurant's dinner service into closing,
  /// not just a fixed clock cutoff.
  static const int eveningStartHour = 18;
  static const int eveningEndHour = 5;

  static const double _backgroundBlend = 0.14;
  static const double _primaryBlend = 0.30;
  static const double _accentBlend = 0.25;

  static const QrMenuAmbientPalette _daytime = QrMenuAmbientPalette(
    background: QrMenuColors.background,
    primary: QrMenuColors.primary,
    accent: QrMenuColors.gold,
  );

  /// Resolves the palette for [hour] (24h, `0`–`23`).
  static QrMenuAmbientPalette forHour(int hour) {
    assert(hour >= 0 && hour <= 23, 'hour must be 0-23, got $hour');
    if (!_isEvening(hour)) return _daytime;

    return QrMenuAmbientPalette(
      background: Color.lerp(
        QrMenuColors.background,
        QrMenuColors.primaryDeep,
        _backgroundBlend,
      )!,
      primary: Color.lerp(
        QrMenuColors.primary,
        QrMenuColors.primaryDeep,
        _primaryBlend,
      )!,
      accent: Color.lerp(
        QrMenuColors.gold,
        QrMenuColors.terracotta,
        _accentBlend,
      )!,
    );
  }

  static bool _isEvening(int hour) =>
      hour >= eveningStartHour || hour < eveningEndHour;
}
