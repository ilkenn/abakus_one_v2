import 'package:flutter/material.dart';
import '../../../../core/config/asset_paths.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';

/// Bowl Builder's static editorial hero (2026-08-08) — a single approved
/// banner image (with its own baked-in typography) temporarily standing in
/// for the live `BowlCanvas` preview at the top of the main editing screen.
/// Purely presentational: no Flutter text/overlay is drawn on top, and it
/// never touches `bowlBuilderProvider` — the live nutrition dashboard right
/// below it (`BowlBuilderLiveMetrics`) is what stays reactive. `BowlCanvas`
/// itself is untouched and still used on the Summary step.
///
/// No explicit width/height is set on the [Image] — as a stretched child of
/// this screen's content column, it fills the available width and sizes
/// its own height from the real file's intrinsic aspect ratio (`BoxFit
/// .contain`, never cropped/distorted). [errorBuilder] only kicks in while
/// `build_your_bowl_banner.webp` hasn't been dropped in yet: a neutral
/// fixed-ratio placeholder, never an icon or a broken-image glyph. Once the
/// real file lands at the exact path below, it renders automatically — no
/// further Dart change needed.
class BuildYourBowlHero extends StatelessWidget {
  const BuildYourBowlHero({super.key});

  static const String _assetPath =
      '${AssetPaths.bannersImageDirectory}build_your_bowl_banner.webp';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.kExtraLarge,
      child: Image.asset(
        _assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        errorBuilder: (context, error, stackTrace) => const AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(color: AppColors.surfaceVariant),
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
