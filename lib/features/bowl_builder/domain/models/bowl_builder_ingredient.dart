/// A single selectable Bowl Builder ingredient — the one place its price
/// lives (product decision, 2026-07-23: no "included"/free tier anywhere in
/// this model; every selected ingredient adds its own [price] to the total,
/// always). Deliberately its own type, not a reuse of
/// `menu/domain/models/modifier_option.dart`'s `ModifierOption` — that model
/// backs Product Detail's real-product modifiers, where "extra price on top
/// of a base price" is the correct meaning; Bowl Builder has no base price
/// to be "extra" on top of, so it gets this separate, explicit model instead
/// of overloading the shared one.
///
/// [caloriesKcal]/[proteinGrams]/[fatGrams]/[carbohydrateGrams] (added for
/// the v2 live nutrition dashboard, 2026-08-08) are **per-selected-portion**
/// values — quantity-N ingredients (Proteinler/Karbonhidratlar) multiply
/// these by N exactly like [price], via the nutrition totals providers in
/// `bowl_builder_provider.dart`. See `bowl_builder_catalog.dart` for the
/// important disclosure that today's values are illustrative development
/// placeholders, not real nutrition data.
class BowlBuilderIngredient {
  final String id;
  final String name;
  final String categoryId;
  final double price;
  final bool isAvailable;
  final String? imageKey;
  final int sortOrder;
  final double caloriesKcal;
  final double proteinGrams;
  final double fatGrams;
  final double carbohydrateGrams;

  const BowlBuilderIngredient({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.price,
    this.isAvailable = true,
    this.imageKey,
    required this.sortOrder,
    required this.caloriesKcal,
    required this.proteinGrams,
    required this.fatGrams,
    required this.carbohydrateGrams,
  });

  BowlBuilderIngredient copyWith({
    String? id,
    String? name,
    String? categoryId,
    double? price,
    bool? isAvailable,
    String? imageKey,
    int? sortOrder,
    double? caloriesKcal,
    double? proteinGrams,
    double? fatGrams,
    double? carbohydrateGrams,
  }) {
    return BowlBuilderIngredient(
      id: id ?? this.id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      price: price ?? this.price,
      isAvailable: isAvailable ?? this.isAvailable,
      imageKey: imageKey ?? this.imageKey,
      sortOrder: sortOrder ?? this.sortOrder,
      caloriesKcal: caloriesKcal ?? this.caloriesKcal,
      proteinGrams: proteinGrams ?? this.proteinGrams,
      fatGrams: fatGrams ?? this.fatGrams,
      carbohydrateGrams: carbohydrateGrams ?? this.carbohydrateGrams,
    );
  }
}
