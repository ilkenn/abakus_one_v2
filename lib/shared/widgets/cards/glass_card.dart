import 'dart:ui';

import 'package:flutter/material.dart';

/// A frosted/translucent "glassmorphism" surface — a blurred backdrop
/// (`BackdropFilter`) behind a semi-opaque [tintColor] fill, clipped to
/// [borderRadius]. Generic by design (Primitive layer, per the Component
/// Design Rules' layer taxonomy): it takes its colors as parameters rather
/// than reading any design-token file itself, so it's reusable by both the
/// default design system and the customer QR-ordering scoped theme
/// (`lib/core/theme/qr_menu_theme.dart`) without this widget ever importing
/// either one — callers own the token choice, this widget only owns the
/// blur/opacity mechanics.
///
/// Intended for small floating overlays (a price/tag badge over a product
/// photo) where the content behind the card is unpredictable (a photo, not
/// a flat token background) — [tintColor] should carry enough opacity
/// (≥~0.6) that the blur+tint combination reads consistently regardless of
/// what's behind it; this widget does not attempt to compute contrast
/// against arbitrary backdrop content itself, that's the caller's
/// responsibility when choosing [tintColor]/[child]'s own foreground color.
class GlassCard extends StatelessWidget {
  final Widget child;
  final Color tintColor;
  final double blurSigma;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Border? border;

  const GlassCard({
    super.key,
    required this.child,
    required this.tintColor,
    this.blurSigma = 12.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tintColor,
            borderRadius: borderRadius,
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}
