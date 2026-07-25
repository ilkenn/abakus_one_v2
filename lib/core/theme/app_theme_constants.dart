class AppThemeConstants {
  const AppThemeConstants._();

  static const double categoryListHeight = 44.0;
  // Sized with headroom for the campaign card's title (1 line) + description
  // (2 lines) at up to ~1.6x accessibility text scale, not just the default
  // scale — a tighter box overflows once the user increases system font
  // size.
  static const double campaignCarouselHeight = 160.0;
  static const double popularProductImageSize = 48.0;

  static const Duration categoryTransitionDuration = Duration(
    milliseconds: 200,
  );

  static const double campaignViewportFraction = 0.9;

  /// Minimum width/height for a compact icon-only tap target (e.g. a
  /// favorite toggle or quantity stepper button packed into a card row).
  /// Below this, touch targets become hard to hit reliably and fail
  /// standard accessibility guidance — use instead of an empty
  /// `BoxConstraints()`, which shrinks the tap area down to the icon's own
  /// (often much smaller) bounds.
  static const double minTapTargetSize = 40.0;
}
