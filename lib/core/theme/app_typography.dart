import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Type scale — `displayLarge`, `displayMedium`, `headlineLarge`,
/// `headlineMedium`, `titleLarge`, `titleMedium`, `bodyLarge`, `bodyMedium`,
/// `bodySmall`, and `caption` are named to map 1:1 onto Master
/// Specification v1.0 §05's Type Scale ("Display Large/Medium", "Heading
/// Large/Medium", "Title Large/Medium", "Body Large/Medium/Small",
/// "Caption") and use exactly its pixel sizes. Every weight is clamped to
/// the spec's enumerated set (400/500/600/700) — the pre-spec 800/900
/// weights this file used are gone.
///
/// **Font family assumption**: the spec calls for "SF Pro Display" (fallback
/// Inter/Roboto) as the primary typeface, but no such font is bundled in
/// `pubspec.yaml`/`assets/` in this repository. Adding real font files (or a
/// package like `google_fonts`) is out of scope for a token-value update —
/// `fontFamily` is deliberately left unset here (Flutter's platform default)
/// until that asset work happens. See `docs/master_spec_migration.md`.
///
/// `labelLarge`, `labelMedium`, `priceLarge`, and `priceMedium` are not
/// named tiers in the spec's type scale. They're kept (screens not yet
/// migrated depend on them) with their sizes untouched, but their weights
/// are still clamped to the spec's 400–700 range.
abstract final class AppTypography {
  AppTypography._();

  static const double _letterSpacingTracking = 2.0;

  static const TextStyle displayLarge = TextStyle(
    fontSize: 40.0,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -1.0,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 34.0,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.8,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontSize: 28.0,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 24.0,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 20.0,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.3,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.2,
  );

  // Not named tiers in the spec's type scale — kept for screens not yet
  // migrated. Sizes untouched; weights clamped to the spec's 400–700 range.
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w600,
    color: AppColors.secondary,
    letterSpacing: _letterSpacingTracking,
  );

  static const TextStyle priceLarge = TextStyle(
    fontSize: 22.0,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle priceMedium = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
