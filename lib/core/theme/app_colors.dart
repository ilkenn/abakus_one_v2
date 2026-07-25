import 'package:flutter/material.dart';

/// Color palette — values for `primary`, `primaryLight`, `primaryExtraLight`,
/// `background`, `surface`, `surfaceVariant`, `border`, `textPrimary`,
/// `textSecondary`, `textDisabled`, `success`, `warning`, and `error` are
/// exactly the hex values defined in Master Specification v1.0 §05
/// (Design System) — Color Palette. Never edit those by hand; they must
/// always equal the spec.
///
/// `onPrimary`, `secondary`, `accent`, `primaryDark`, `divider`, `info`,
/// `overlay`, and `scrim` are not defined by the spec. They're kept at their
/// pre-spec values (needed by screens not yet migrated to this
/// specification) except `onPrimary` (assumed `#FFFFFF` — the only sane
/// reading of "primary" being a dark, saturated green) and `divider`
/// (assumed equal to `border`, since the spec defines only one line-color
/// token, not a separate one for dividers). See
/// `docs/master_spec_migration.md` for the full assumption log.
abstract final class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF355E3B);
  static const Color primaryLight = Color(0xFF6F8F72);
  static const Color primaryExtraLight = Color(0xFFEAF3EC);

  // Not defined by the spec — kept for screens not yet migrated.
  static const Color primaryDark = Color(0xFF003300);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFFE65100);
  static const Color accent = Color(0xFFFF9100);

  static const Color background = Color(0xFFF8F6F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F4F0);

  static const Color textPrimary = Color(0xFF1F2933);
  static const Color textSecondary = Color(0xFF667085);
  static const Color textDisabled = Color(0xFFB8B8B8);

  static const Color border = Color(0xFFE6E2D9);
  static const Color divider = Color(0xFFE6E2D9);

  static const Color success = Color(0xFF3C8D40);
  static const Color warning = Color(0xFFF5A524);
  static const Color error = Color(0xFFD9534F);

  // Not defined by the spec — kept for screens not yet migrated.
  static const Color info = Color(0xFF1565C0);
  static const Color overlay = Color(0x66000000);
  static const Color scrim = Color(0x99000000);
}
