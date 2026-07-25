/// Optional nutritional information for a [MenuProduct]. Every field is
/// nullable — most products won't have this populated yet, and the UI must
/// simply omit the row when it's absent, not show zeros.
class ProductNutrition {
  final int? calories;
  final double? proteinGrams;
  final double? carbsGrams;
  final double? fatGrams;

  const ProductNutrition({
    this.calories,
    this.proteinGrams,
    this.carbsGrams,
    this.fatGrams,
  });

  /// Whether there is anything to actually display.
  bool get hasAnyValue =>
      calories != null ||
      proteinGrams != null ||
      carbsGrams != null ||
      fatGrams != null;
}
