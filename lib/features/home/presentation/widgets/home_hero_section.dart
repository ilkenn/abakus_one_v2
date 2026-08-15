import 'package:flutter/material.dart';
import '../../../../core/config/asset_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/images/app_cover_image.dart';

/// The Home screen's primary hero — "Kendi Bowl'unu Yarat". Designed to
/// receive a real photography asset later without any layout change: the
/// background is a plain `Image.asset` at [AssetPaths.homeImageDirectory]
/// `home_hero.webp` with a neutral placeholder `errorBuilder` fallback
/// while that file doesn't exist yet. Title/subtitle/CTA are real Flutter
/// widgets layered over it — never baked into the image.
class HomeHeroSection extends StatelessWidget {
  final VoidCallback onCreateBowlTap;

  const HomeHeroSection({super.key, required this.onCreateBowlTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.kExtraLarge,
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const AppCoverImage(
              assetPath: '${AssetPaths.homeImageDirectory}home_hero.webp',
              placeholderColor: AppColors.surfaceVariant,
            ),
            // Scrim so title/CTA stay legible once a real photo replaces
            // the neutral placeholder above.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x99000000)],
                  stops: [0.35, 1.0],
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Kendi Bowl\'unu Yarat',
                    style: AppTypography.headlineLarge.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Malzemeni seç, dakikalar içinde hazır.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton(
                    onPressed: onCreateBowlTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.kExtraLarge,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: AppSpacing.md,
                      ),
                    ),
                    child: const Text('Bowl\'unu Oluştur'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
