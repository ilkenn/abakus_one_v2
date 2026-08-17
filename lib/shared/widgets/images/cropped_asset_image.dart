import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Renders only a fractional sub-rectangle of an asset image, scaled to
/// fill this widget's own box exactly (an arbitrary-rect analogue of
/// `BoxFit.cover`, since Flutter has no built-in "cover a crop rect"
/// fit). Used when a source banner/illustration carries baked-in text or
/// content in part of the frame that must never render on screen — the
/// crop guarantees that content is never painted at all, not merely
/// covered by something else.
///
/// The parent should size this widget's box to the same aspect ratio as
/// the crop rect itself (`(cropX1 - cropX0) * sourceAspectRatio /
/// (cropY1 - cropY0)`) so the fill is exact with no extra overflow to
/// clip in the non-cropped axis — typically via an outer `AspectRatio`.
class CroppedAssetImage extends StatelessWidget {
  const CroppedAssetImage({
    super.key,
    required this.assetPath,
    required this.sourceAspectRatio,
    required this.cropX0,
    required this.cropX1,
    required this.cropY0,
    required this.cropY1,
  });

  final String assetPath;
  final double sourceAspectRatio;
  final double cropX0;
  final double cropX1;
  final double cropY0;
  final double cropY1;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boxWidth = constraints.maxWidth;
          final cropWidthFraction = cropX1 - cropX0;
          // Uniform scale: the caller's box already matches the crop
          // rect's own aspect ratio, so deriving scale from width alone
          // yields a matching height too.
          final renderedWidth = boxWidth / cropWidthFraction;
          final renderedHeight = renderedWidth / sourceAspectRatio;
          return Stack(
            children: [
              Positioned(
                left: -cropX0 * renderedWidth,
                top: -cropY0 * renderedHeight,
                width: renderedWidth,
                height: renderedHeight,
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                  isAntiAlias: true,
                  errorBuilder: (context, error, stackTrace) =>
                      const ColoredBox(color: AppColors.primaryExtraLight),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
