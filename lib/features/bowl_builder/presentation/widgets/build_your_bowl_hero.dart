import 'package:flutter/material.dart';
import '../../../../core/config/asset_paths.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../shared/widgets/images/cropped_asset_image.dart';

/// Bowl Builder's static editorial hero (2026-08-08, compacted B.1
/// 2026-08-17) — a single approved banner image standing in for the live
/// `BowlCanvas` preview at the top of the main editing screen. Purely
/// presentational: no Flutter text/overlay is drawn on top, and it never
/// touches `bowlBuilderProvider` — `BowlCanvas` itself is untouched and
/// still drives the live preview on the Summary step.
///
/// B.1: the original full 3:2 artwork at `BoxFit.contain` rendered ~218px
/// tall on a 375px phone, pushing the first ingredient choices well below
/// the fold. The artwork's own baked headline ("Kendi Bowlunu Yarat") is
/// also redundant with the screen's own `AppBar` title — so rather than
/// shrinking the whole banner (which would make that baked text
/// illegible), this crops to a confirmed-safe, text-free slice of the
/// bowl photography itself (avocado/chicken/chickpeas/cabbage — the most
/// colorful, appetizing part of the source image), sized to a fixed
/// compact aspect ratio via [CroppedAssetImage] — which carries its own
/// neutral-tint fallback if the asset is ever missing, same safety net
/// the previous full-artwork version had.
class BuildYourBowlHero extends StatelessWidget {
  const BuildYourBowlHero({super.key});

  static const String _assetPath =
      '${AssetPaths.bannersImageDirectory}build_your_bowl_banner.webp';

  static const double _sourceAspectRatio = 1536 / 1024;

  /// Right ~54% of the source (past the "Kendi Bowlunu Yarat" headline,
  /// which ends at roughly x=0.44) and a vertically-centered band over
  /// the bowl's most colorful contents — measured by direct visual
  /// inspection of the asset.
  static const double _cropX0 = 0.46;
  static const double _cropX1 = 1.0;
  static const double _cropY0 = 0.35;
  static const double _cropY1 = 0.684;
  static const double _cropAspectRatio =
      ((_cropX1 - _cropX0) * _sourceAspectRatio) / (_cropY1 - _cropY0);

  /// Caps the hero's own width (independent of the screen's — this
  /// screen has no shared max-content-width container) so the fixed
  /// aspect ratio yields a "compact" height on phone (~135px at a
  /// typical 327px content width) without growing unboundedly on a wide
  /// viewport — capped at a "slightly larger" ~174px instead.
  static const double _maxWidth = 420;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: const AspectRatio(
          aspectRatio: _cropAspectRatio,
          child: ClipRRect(
            borderRadius: AppRadius.kExtraLarge,
            child: CroppedAssetImage(
              assetPath: _assetPath,
              sourceAspectRatio: _sourceAspectRatio,
              cropX0: _cropX0,
              cropX1: _cropX1,
              cropY0: _cropY0,
              cropY1: _cropY1,
            ),
          ),
        ),
      ),
    );
  }
}
