import 'package:flutter/material.dart';
import '../../../../core/config/asset_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/images/app_cover_image.dart';

/// The large premium Bowl Builder feature banner — a distinct component
/// from the shared `BowlBuilderFeatureCard` (used on Menu) because this one
/// is specifically asset-integration-ready (a real background photo slot),
/// which would be an unrelated visual change to Menu's own card if made to
/// the shared widget instead.
class BuildBowlBanner extends StatelessWidget {
  final VoidCallback onTap;

  const BuildBowlBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Kendi Bowl\'unu Yarat, Bowl\'unu Oluştur',
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.kExtraLarge,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.kExtraLarge,
          child: ClipRRect(
            borderRadius: AppRadius.kExtraLarge,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const AppCoverImage(
                    assetPath:
                        '${AssetPaths.homeImageDirectory}build_bowl_banner.webp',
                    placeholderColor: AppColors.primaryExtraLight,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0xCC000000), Colors.transparent],
                        stops: [0.0, 0.8],
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    top: AppSpacing.lg,
                    bottom: AppSpacing.lg,
                    // H.1 responsive audit: at narrow (phone) widths this
                    // banner's own height shrinks with it (fixed 16:9
                    // AspectRatio), which previously threw a RenderFlex
                    // overflow — title+subtitle+button no longer fit the
                    // shrunk, top+bottom-pinned Positioned box.
                    // SingleChildScrollView makes this a no-op everywhere
                    // it already fit (content shorter than the box never
                    // shows a scrollbar) and simply scrolls rather than
                    // overflows on the narrowest phones or largest text-
                    // scale settings, instead of throwing.
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Kendi Bowl\'unu Yarat',
                            style: AppTypography.titleLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Malzemeni seç, fiyatını anında gör. Tamamen '
                            'sana özel hazırla.',
                            style: AppTypography.bodySmall.copyWith(
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ElevatedButton(
                            onPressed: onTap,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primary,
                              shape: const RoundedRectangleBorder(
                                borderRadius: AppRadius.kExtraLarge,
                              ),
                            ),
                            child: const Text('Bowl\'unu Oluştur'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
