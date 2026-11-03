import 'package:flutter/material.dart';

/// Maps a `MenuProduct.allergens` entry (plain Turkish text, see that
/// field's own doc comment) to a small pictogram — product owner,
/// 2026-11-03, replacing a generic "⚠️" triangle everywhere allergens are
/// shown.
///
/// Only the five allergens the product owner gave an explicit icon for
/// (gluten/süt/susam/balık/yumurta) have a confident, assigned symbol.
/// 'hardal'/'soya'/'ceviz' have real catalog data (the 2026-11-03 PDF
/// import) but no pictogram was specified for them — they fall back to
/// [fallbackIcon], a generic marker, rather than guessing a specific
/// symbol for an allergen type nobody picked an icon for yet.
abstract final class AllergenIcons {
  AllergenIcons._();

  static const IconData fallbackIcon = Icons.circle_outlined;

  static const Map<String, IconData> _iconByAllergen = {
    'gluten': Icons.grain,
    'süt': Icons.local_drink,
    'susam': Icons.spa,
    'balık': Icons.phishing,
    'yumurta': Icons.egg_outlined,
  };

  static IconData iconFor(String allergen) =>
      _iconByAllergen[allergen] ?? fallbackIcon;
}
