/// Standardized nutrition values for one [NutritionReferenceEntry],
/// always expressed per 100 units of its `referenceUnit` (100g or
/// 100ml) — Phase 7 (`docs/decisions.md` ADR-024). Every field is
/// nullable — a source may not report every value, and a missing
/// field must stay honestly missing, never defaulted to zero (7J's
/// calculation engine is the one place that turns "missing" into an
/// explicit incomplete-data warning).
///
/// Mass-based fields are integer milligrams (never a `double` gram
/// value) — the same exact-integer discipline `Money`/`Quantity`
/// already follow. Energy is integer kilocalories, already
/// whole-number granularity in practice.
class NutritionValueSet {
  const NutritionValueSet({
    this.energyKcal,
    this.proteinMilligrams,
    this.carbohydrateMilligrams,
    this.fatMilligrams,
    this.saturatedFatMilligrams,
    this.fiberMilligrams,
    this.sugarMilligrams,
    this.saltMilligrams,
    this.sodiumMilligrams,
  });

  final int? energyKcal;
  final int? proteinMilligrams;
  final int? carbohydrateMilligrams;
  final int? fatMilligrams;
  final int? saturatedFatMilligrams;
  final int? fiberMilligrams;
  final int? sugarMilligrams;
  final int? saltMilligrams;
  final int? sodiumMilligrams;

  /// `true` only when every field is present — 7J uses this to decide
  /// whether a per-ingredient contribution is exact or must flag the
  /// aggregate result as incomplete.
  bool get isComplete =>
      energyKcal != null &&
      proteinMilligrams != null &&
      carbohydrateMilligrams != null &&
      fatMilligrams != null &&
      saturatedFatMilligrams != null &&
      fiberMilligrams != null &&
      sugarMilligrams != null &&
      saltMilligrams != null &&
      sodiumMilligrams != null;
}
