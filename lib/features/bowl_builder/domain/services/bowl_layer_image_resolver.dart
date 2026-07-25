import '../../../../core/config/asset_paths.dart';

/// Builds the two kinds of paths [BowlCanvas] renders — the bowl base and
/// per-ingredient overlay layers — for the upcoming official Abaküs
/// Ingredient Asset Library (Faz 8.2, 2026-07-24).
///
/// Deliberately NOT a maintained registry like `IngredientImageResolver`:
/// every path here is *derived*, not looked up, so dropping the real,
/// transparent, identically-sized PNG library into `assets/images/bowl/`
/// later needs zero Dart changes. `BowlCanvas` already calls `Image.asset`
/// on the exact path a real file would use; today that call simply fails
/// (caught by its `errorBuilder`, since nothing exists there yet) and
/// starts succeeding the moment a real file lands at that same path — no
/// registry entry, no key to add, nothing to edit here ever again.
abstract final class BowlLayerImageResolver {
  BowlLayerImageResolver._();

  /// The single bowl base image, rendered exactly once by [BowlCanvas].
  static String bowlBasePath() =>
      '${AssetPaths.bowlImageDirectory}bowl_empty.png';

  /// One ingredient's transparent overlay — [imageKey] is the same key
  /// already carried by `BowlBuilderIngredient.imageKey`, reused as-is
  /// (never a separate key to maintain).
  static String layerPath(String imageKey) =>
      '${AssetPaths.bowlImageDirectory}layers/$imageKey.png';
}
