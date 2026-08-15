import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// A reusable "fills its box, cropped, never distorted" image — the single
/// place `ClipRRect` + `BoxFit.cover` + a fade-in + an error placeholder +
/// `FilterQuality.high` are wired together. Used for full-bleed photo
/// backgrounds (Home's hero and Bowl Builder banner) where cropping to fill
/// is exactly what's wanted.
///
/// **Not** for editorial/promotional artwork that may carry its own baked-
/// in text (order-mode cards, category cards) — those must never be
/// cropped, so they use [EditorialAssetCard] (`BoxFit.contain`) instead.
/// Product photography stays on this widget; editorial banners don't.
///
/// [placeholderIcon] is optional — the hero/banner backgrounds show a bare
/// neutral tint with no icon (an icon in a full-bleed background would read
/// as a broken-image glyph, not a placeholder), while smaller card/thumbnail
/// slots pass an icon so the placeholder still communicates *what* goes
/// there.
class AppCoverImage extends StatelessWidget {
  final String assetPath;
  final BorderRadius borderRadius;
  final IconData? placeholderIcon;
  final Color placeholderColor;

  const AppCoverImage({
    super.key,
    required this.assetPath,
    this.borderRadius = BorderRadius.zero,
    this.placeholderIcon,
    this.placeholderColor = AppColors.surfaceVariant,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.asset(
        assetPath,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        errorBuilder: (context, error, stackTrace) => Container(
          color: placeholderColor,
          alignment: Alignment.center,
          child: placeholderIcon == null
              ? null
              : Icon(placeholderIcon, color: AppColors.primary),
        ),
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: child,
          );
        },
      ),
    );
  }
}
