import 'package:flutter/material.dart';
import '../../../../core/config/asset_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/images/cropped_asset_image.dart';
import 'home_section_title.dart';

/// "Topluluk & Yorumlar" — H.2.1 rebuild, H.2.2 visual-weight pass. No
/// community/review screen or real review data exists yet (confirmed by
/// exhaustive search in the H.0 audit); this is the Home *presentation*
/// shell only, built ahead of the real feature (H.5).
///
/// H.2's first attempt showed a large cropped panel of `banner_05.png`'s
/// own headline text, which physical review found visibly cut off and
/// unacceptable. H.2.1 replaced that with real Flutter headline/support
/// text (never baked artwork text, so it can never be clipped) plus a
/// small safe decorative crop; physical review then found that version
/// too small/visually weak. H.2.2 keeps the same safe crop rectangle
/// (still confirmed clear of every baked reviewer name/rating/count/
/// phone-mockup element — the phone's own right edge sits at roughly
/// x=0.81 of the source image, so this crop's `x0=0.83` keeps a
/// deliberate safety margin) but displays it larger, as a tall side
/// strip rather than a small leading icon, and gives the headline
/// stronger typographic weight. No CTA is wired yet — there's nowhere
/// real for it to go — so this card is a plain, non-interactive preview.
class CommunityPreviewSection extends StatelessWidget {
  const CommunityPreviewSection({super.key});

  static const double _sourceAspectRatio = 1774 / 887;

  /// Top-right olive-leaf spray, past the phone mockup's right edge and
  /// above the bottom-right ingredient-bowl photo.
  static const double _cropX0 = 0.83;
  static const double _cropX1 = 1.0;
  static const double _cropY0 = 0.0;
  static const double _cropY1 = 0.58;
  static const double _cropAspectRatio =
      ((_cropX1 - _cropX0) * _sourceAspectRatio) / (_cropY1 - _cropY0);

  static const double _cardHeight = 184;
  static const double _imageStripWidth = _cardHeight * _cropAspectRatio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionTitle('Topluluk & Yorumlar'),
        Container(
          // H.2.2: a fixed, taller card height (168, up from the previous
          // ~72px min-content row) — a direct height/width pair rather
          // than `IntrinsicHeight` + `AspectRatio`, which would otherwise
          // need to resolve a circular "image's preferred size depends on
          // the row's height, which depends on the image's intrinsic
          // height" before either side can lay out.
          height: _cardHeight,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.kExtraLarge,
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  // Center + SingleChildScrollView rather than a plain
                  // Column(mainAxisAlignment: center): at large
                  // accessibility text scales the headline/support/badge
                  // stack can exceed the card's fixed compact height —
                  // this scrolls instead of throwing a RenderFlex
                  // overflow, while looking identical (centered, no
                  // visible scroll affordance) at every normal text
                  // scale. Same pattern as the hero carousel's mobile
                  // slide.
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Gerçek Yorumlar, Gerçek Lezzetler',
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.primary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Abaküs topluluğunda deneyimler yakında burada '
                            'buluşacak.',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 4,
                            ),
                            decoration: const BoxDecoration(
                              color: AppColors.primaryExtraLight,
                              borderRadius: AppRadius.kPill,
                            ),
                            child: Text(
                              'Yakında',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(
                width: _imageStripWidth,
                child: CroppedAssetImage(
                  assetPath: '${AssetPaths.homeBannerDirectory}banner_05.png',
                  sourceAspectRatio: _sourceAspectRatio,
                  cropX0: _cropX0,
                  cropX1: _cropX1,
                  cropY0: _cropY0,
                  cropY1: _cropY1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
