import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import 'product_image_source.dart';

/// Renders a product's image by [imageKey], resolved through
/// [productImageSourceProvider] — never asks where the image actually comes
/// from (local asset today; a CDN/Firebase Storage-backed source later
/// without this widget changing at all). Falls back to an icon-on-tint
/// placeholder — matching the pattern already used across Home/Menu — when
/// no real image exists for that key, instead of a broken image or a
/// hardcoded fallback path.
///
/// [width]/[height] also bound decode size via `cacheWidth`/`cacheHeight`
/// (scaled by the device's pixel ratio) — the bundled source photos are
/// several megabytes each at full resolution, so decoding them at their
/// actual display size instead of native size meaningfully cuts memory and
/// jank risk in image-heavy lists.
///
/// [heroTag], when given, wraps the resolved image in a [Hero] — used to
/// animate a product's photo between its list card and its detail screen.
/// `null` (the default) renders exactly as before, no Hero involved, so
/// existing call sites are unaffected until they opt in.
class ProductImage extends ConsumerWidget {
  final String imageKey;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final double placeholderIconSize;
  final Object? heroTag;

  const ProductImage({
    super.key,
    required this.imageKey,
    this.width,
    this.height,
    this.borderRadius = AppRadius.kMedium,
    this.placeholderIconSize = 36,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(productImageSourceProvider);
    final resolved = source.resolve(imageKey);
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = (width != null && width!.isFinite)
        ? (width! * devicePixelRatio).round()
        : null;
    final cacheHeight = (height != null && height!.isFinite)
        ? (height! * devicePixelRatio).round()
        : null;
    // ResizeImage is a decorator that works with any ImageProvider
    // subtype — this is what lets cacheWidth/cacheHeight apply regardless
    // of whether `resolved` is a local AssetImage or a future
    // network/CDN-backed provider, with no widget-level branching.
    final provider = resolved == null
        ? null
        : ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, resolved);

    final content = provider != null
        ? Image(
            image: provider,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _placeholder(),
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: child,
              );
            },
          )
        : _placeholder();

    final clipped = ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(width: width, height: height, child: content),
    );

    return heroTag == null ? clipped : Hero(tag: heroTag!, child: clipped);
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.1),
      child: Icon(
        Icons.fastfood_rounded,
        color: AppColors.primary,
        size: placeholderIconSize,
      ),
    );
  }
}
