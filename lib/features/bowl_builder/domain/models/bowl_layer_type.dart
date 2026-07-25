import '../../data/bowl_builder_catalog.dart';

/// The six visual layers a rendered bowl is composed of, drawn on top of
/// `bowl_empty.png` in this exact order (Faz 8.2, 2026-07-24 — architectural
/// preparation for the official Abaküs Ingredient Asset Library). [values]
/// itself IS the render order: base first, topping last — see [BowlCanvas].
///
/// Deliberately fewer than the picker's 9 catalog categories
/// ([kCategoryProtein] etc.): several categories collapse into one visual
/// layer since, on the actual bowl, they'd stack the same way. See
/// [forCategoryId] for the exact mapping.
enum BowlLayerType {
  base,
  protein,
  vegetable,
  cheese,
  sauce,
  topping;

  /// Maps a [BowlBuilderCategory.id] to the layer its ingredients draw on.
  /// Every one of the 9 catalog category ids must resolve here — this
  /// throws for an id it doesn't recognize rather than silently dropping a
  /// selected ingredient off the rendered bowl.
  static BowlLayerType forCategoryId(String categoryId) {
    switch (categoryId) {
      case kCategoryCarbs:
        return BowlLayerType.base;
      case kCategoryProtein:
        return BowlLayerType.protein;
      case kCategorySalads:
      case kCategoryVegetables:
      case kCategoryFruits:
      case kCategoryPickles:
        return BowlLayerType.vegetable;
      case kCategoryCheeses:
        return BowlLayerType.cheese;
      case kCategorySauces:
        return BowlLayerType.sauce;
      case kCategoryOthers:
        return BowlLayerType.topping;
      default:
        throw ArgumentError.value(
          categoryId,
          'categoryId',
          'Unknown Bowl Builder category id — add it to BowlLayerType.forCategoryId',
        );
    }
  }
}
