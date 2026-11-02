import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/bowl_builder/domain/services/ingredient_image_resolver.dart';
import '../../../features/menu/domain/services/menu_image_resolver.dart';

/// Resolves a product's `imageKey` to a Flutter [ImageProvider] — the single
/// seam between "where product photos actually come from" and every widget
/// that displays one ([ProductImage]).
///
/// Returning an [ImageProvider] rather than a path/URL string is what makes
/// this future-proof: [AssetImage] (today), [NetworkImage], or a CDN/Firebase
/// Storage-backed provider (later) are all just different [ImageProvider]
/// subtypes. `ProductImage` renders whatever it's given via Flutter's own
/// generic `Image(image: ...)` constructor, so switching sources is a change
/// to `productImageSourceProvider`'s implementation alone — no UI code
/// changes, mirroring the same repository-provider pattern already used by
/// `ordersRepositoryProvider`/`authRepositoryProvider`/
/// `bowlBuilderCatalogRepositoryProvider`.
abstract interface class ProductImageSource {
  /// Every image provider worth trying for [imageKey], in order — empty
  /// if none exist. [categoryId] (a real `MenuCategory.id`) opts into the
  /// newer per-category menu-photo convention; see
  /// [MenuImageResolver.resolveCandidates] for why this is a list rather
  /// than a single nullable result. Callers render a placeholder once
  /// every candidate here has failed to load.
  List<ImageProvider> resolveCandidates(String imageKey, {String? categoryId});
}

/// Today's only implementation — resolves against the bundled
/// `assets/menu/`/`assets/images/menu/` (real dishes, via
/// [MenuImageResolver]) and `assets/images/products/` (Bowl Builder
/// ingredients, via [IngredientImageResolver]) directories. The key
/// namespaces don't collide (menu keys are hyphenated, e.g.
/// `mexifit-bowl`; ingredient keys are snake_case, e.g. `izgara_tavuk`),
/// so checking both here is safe and keeps [ProductImage] a single,
/// feature-agnostic widget.
class LocalAssetProductImageSource implements ProductImageSource {
  const LocalAssetProductImageSource();

  @override
  List<ImageProvider> resolveCandidates(String imageKey, {String? categoryId}) {
    final menuCandidates =
        MenuImageResolver.resolveCandidates(imageKey, categoryId: categoryId);
    if (menuCandidates.isNotEmpty) {
      return [for (final path in menuCandidates) AssetImage(path)];
    }
    final ingredientPath = IngredientImageResolver.resolve(imageKey);
    if (ingredientPath != null) return [AssetImage(ingredientPath)];
    return const [];
  }
}

final productImageSourceProvider = Provider<ProductImageSource>((ref) {
  return const LocalAssetProductImageSource();
});
