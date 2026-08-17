import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// One compact order-mode grid cell — H.2. The source artwork
/// (`assets/images/home/order_modes/*.webp`) is a full editorial banner
/// with its own baked-in headline/subtitle, sized for the old wide
/// horizontal-scroll card; a 2×2 grid cell is too small to show that text
/// legibly, so this cover-crops toward the artwork's photography half
/// (`Alignment.centerRight`, away from its baked-in headline on the left)
/// and pairs it with a short, separately-rendered Flutter label — the
/// same "image + short label" split [EditorialAssetCard] already uses
/// elsewhere, just cropped rather than letterboxed, to fit a genuinely
/// compact cell.
class OrderModeGridCard extends StatelessWidget {
  const OrderModeGridCard({
    super.key,
    required this.assetPath,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final String assetPath;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadius.kLarge,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.kLarge,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.kLarge,
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            clipBehavior: Clip.antiAlias,
            // Column fills the grid cell exactly (Expanded image + a
            // fixed-height label row) rather than a fixed-AspectRatio
            // image atop a min-sized label — H.2.1: the old combination
            // could leave the Container shorter than the grid cell,
            // showing as dead space under the image. The image now always
            // occupies whatever height is left over, so there's none.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ColoredBox(
                    color: AppColors.primaryExtraLight,
                    child: Image.asset(
                      assetPath,
                      fit: BoxFit.cover,
                      alignment: Alignment.centerRight,
                      filterQuality: FilterQuality.high,
                      isAntiAlias: true,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Icon(icon, color: AppColors.primary, size: 28),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: AppColors.primary, size: 14),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          title,
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
