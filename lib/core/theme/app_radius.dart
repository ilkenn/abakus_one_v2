import 'package:flutter/material.dart';

/// `small`, `medium`, `large`, and `extraLarge` are exactly Master
/// Specification v1.0 §05's Radius Tokens (`8, 12, 16, ..., 40`) — `medium`/
/// `large`/`extraLarge` already matched; `small` moved from a pre-spec `6`
/// to the spec's nearest defined value, `8`. `pill` (`99`) isn't one of the
/// spec's discrete radius tokens — it's a shape utility for fully-rounded
/// elements (chips, pill buttons), not a size choice, so it's kept as-is.
abstract final class AppRadius {
  AppRadius._();

  static const double small = 8.0;
  static const double medium = 12.0;
  static const double large = 16.0;
  static const double extraLarge = 24.0;
  static const double pill = 99.0;

  // --- COMPILER INTEGRITY CHECK: TÜM SARMALLAR STATIC CONST OLARAK MÜHÜRLENDİ ---
  static const BorderRadius kSmall = BorderRadius.all(Radius.circular(small));
  static const BorderRadius kMedium = BorderRadius.all(Radius.circular(medium));
  static const BorderRadius kLarge = BorderRadius.all(Radius.circular(large));
  static const BorderRadius kExtraLarge = BorderRadius.all(
    Radius.circular(extraLarge),
  );
  static const BorderRadius kPill = BorderRadius.all(Radius.circular(pill));
}
