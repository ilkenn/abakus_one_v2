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
  /// The image provider for [imageKey], or `null` if no image exists for
  /// this key — callers render a placeholder in that case, never a guessed
  /// path/URL.
  ImageProvider? resolve(String imageKey);
}

/// Today's only implementation — resolves against the bundled
/// `assets/images/menu/` (real dishes, via [MenuImageResolver]) and
/// `assets/images/products/` (Bowl Builder ingredients, via
/// [IngredientImageResolver]) directories. The two key namespaces don't
/// collide (menu keys are hyphenated, e.g. `mexifit-bowl`; ingredient keys
/// are snake_case, e.g. `izgara_tavuk`), so checking both here is safe and
/// keeps [ProductImage] a single, feature-agnostic widget.
class LocalAssetProductImageSource implements ProductImageSource {
  const LocalAssetProductImageSource();

  @override
  ImageProvider? resolve(String imageKey) {
    final menuPath = MenuImageResolver.resolve(imageKey);
    if (menuPath != null) return AssetImage(menuPath);
    final ingredientPath = IngredientImageResolver.resolve(imageKey);
    if (ingredientPath != null) return AssetImage(ingredientPath);
    return null;
  }
}

final productImageSourceProvider = Provider<ProductImageSource>((ref) {
  return const LocalAssetProductImageSource();
});
