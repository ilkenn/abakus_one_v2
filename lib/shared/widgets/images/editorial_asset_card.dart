import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A reusable "show the complete editorial artwork, never crop it" card —
/// for wide promotional/category banners that may carry their own baked-in
/// text, as opposed to plain product photography (which stays
/// `BoxFit.cover` via `AppCoverImage`). Deliberately a *different* image
/// treatment from `AppCoverImage`: this one always uses `BoxFit.contain`
/// against a soft sage backdrop at the asset's own [aspectRatio], so
/// nothing embedded in the source art is ever cut off, stretched, or
/// letterboxed against a mismatched background.
///
/// Home H.1.1 — the image frame carries a restrained premium treatment
/// (hairline border, soft `AppShadows.card`) shared by every consumer
/// (order-mode cards, category cards) so they read as one coherent card
/// family. Both additions are layout-neutral by construction — the border
/// paints on the frame's own edge and the shadow paints outside its bounds
/// — so callers that size this card via a fixed-height row (see
/// `HomeCategorySection`) never need to budget extra space for it.
class EditorialAssetCard extends StatelessWidget {
  final String assetPath;
  final double aspectRatio;
  final BorderRadius borderRadius;
  final String? title;
  final IconData? placeholderIcon;
  final VoidCallback? onTap;

  const EditorialAssetCard({
    super.key,
    required this.assetPath,
    required this.aspectRatio,
    this.borderRadius = AppRadius.kLarge,
    this.title,
    this.placeholderIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.card,
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Container(
                color: AppColors.primaryExtraLight,
                alignment: Alignment.center,
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  isAntiAlias: true,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: AppColors.primaryExtraLight,
                    alignment: Alignment.center,
                    child: placeholderIcon == null
                        ? null
                        : Icon(placeholderIcon, color: AppColors.primary),
                  ),
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                    if (wasSynchronouslyLoaded) return child;
                    return AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      child: child,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (title != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            title!,
            style: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    if (onTap == null) return content;

    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: content,
        ),
      ),
    );
  }
}
