import 'package:flutter/material.dart';
import '../../../../core/config/asset_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';

/// The single "Kendi Bowl'unu Yarat" promo on Home — H.2 consolidation.
/// Previously two separate components (`HomeHeroSection`, a 4:5 full-bleed
/// hero, and `BuildBowlBanner`, a 16:9 banner) both referenced
/// `assets/images/home/home_hero.webp`/`build_bowl_banner.webp`, neither of
/// which has ever actually existed on disk (both always rendered their own
/// placeholder fallback — confirmed by directory listing, not assumed).
/// This card instead uses the one real, already-shipped Bowl Builder asset
/// — `assets/images/banners/build_your_bowl_banner.webp` (1536×1024,
/// verified via direct WebP-header inspection), added 2026-08-08 for a
/// prior Bowl Builder integration and never wired into Home. That artwork
/// carries its own headline/subtitle but, unlike the hero-carousel
/// banners, no baked-in CTA button — so a real, visible Flutter button is
/// correct here, not a duplicate.
///
/// Deliberately considerably shorter than the old 4:5 hero: this card uses
/// the asset's own native 1536:1024 (3:2) ratio via `BoxFit.contain`
/// (never cropped/stretched), so the whole viewport height it occupies is
/// driven by the real artwork's own proportions, not an arbitrarily tall
/// full-bleed choice.
class CompactBowlBuilderCard extends StatelessWidget {
  const CompactBowlBuilderCard({super.key, required this.onTap});

  final VoidCallback onTap;

  static const double _assetAspectRatio = 1536 / 1024;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Kendi Bowl\'unu Yarat, malzemeni seç, Bowl\'unu Oluştur',
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.kExtraLarge,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.kExtraLarge,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.kExtraLarge,
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            child: ClipRRect(
              borderRadius: AppRadius.kExtraLarge,
              child: AspectRatio(
                aspectRatio: _assetAspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: AppColors.background,
                      child: Image.asset(
                        '${AssetPaths.bannersImageDirectory}'
                        'build_your_bowl_banner.webp',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        isAntiAlias: true,
                        errorBuilder: (context, error, stackTrace) =>
                            const ColoredBox(
                          color: AppColors.primaryExtraLight,
                          child: Center(
                            child: Icon(
                              Icons.ramen_dining_rounded,
                              color: AppColors.primary,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.lg,
                      bottom: AppSpacing.lg,
                      child: ElevatedButton(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.kExtraLarge,
                          ),
                        ),
                        child: const Text('Bowl\'unu Oluştur'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
