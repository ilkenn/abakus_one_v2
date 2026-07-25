/// Centralized asset path constants, per `docs/architecture_bible.md` §13 —
/// screens must never hardcode `assets/...` string literals directly.
///
/// Only holds directory/static constants. Per-product image resolution
/// (which file a given product maps to, with placeholder fallback) is
/// `MenuImageResolver`'s job, not this file's — that lookup is dynamic and
/// belongs with the menu domain, not a flat constants list.
abstract final class AssetPaths {
  AssetPaths._();

  static const String menuImageDirectory = 'assets/images/menu/';

  /// Bowl Builder ingredient photos — declared in `pubspec.yaml` since the
  /// Home redesign phase, still empty until real photos are supplied. See
  /// `IngredientImageResolver`.
  static const String productsImageDirectory = 'assets/images/products/';

  /// Layered bowl-compositor art (Faz 8.2, 2026-07-24) — `bowl_empty.png`
  /// plus one transparent overlay per ingredient under `layers/`, both
  /// still empty until the official Abaküs Ingredient Asset Library is
  /// supplied. See `BowlLayerImageResolver`/`BowlCanvas`.
  static const String bowlImageDirectory = 'assets/images/bowl/';
}
