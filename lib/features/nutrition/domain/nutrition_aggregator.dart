import '../../recipes/domain/flattened_ingredient_line.dart';
import 'nutrition_confidence.dart';
import 'nutrition_reference_entry.dart';
import 'nutrition_value_set.dart';

/// The result of `NutritionAggregator.aggregate` — Phase 7
/// (`docs/decisions.md` ADR-024). Transient; `CalculateRecipeNutrition`
/// turns it into a persisted `NutritionCalculationResult`.
class NutritionAggregationOutcome {
  const NutritionAggregationOutcome({
    required this.totalValues,
    required this.missingIngredientIds,
    required this.confidence,
  });

  final NutritionValueSet totalValues;
  final List<String> missingIngredientIds;
  final NutritionConfidence confidence;
}

/// Pure, synchronous aggregation of a flattened ingredient list into
/// total [NutritionValueSet] values — Phase 7 (`docs/decisions.md`
/// ADR-024). No I/O of its own (the caller pre-fetches every
/// [NutritionReferenceEntry] it needs) — reusable by both
/// `CalculateRecipeNutrition` (a static [Recipe]) and, in the future,
/// a Bowl Builder snapshot's resolved ingredient lines (7H) without
/// depending on either feature's repositories.
///
/// An ingredient only contributes when a matching, *complete*
/// [NutritionReferenceEntry] exists **and** its [referenceUnit]
/// matches the flattened line's [Quantity.unit] exactly — this phase
/// does not attempt a cross-dimension (e.g. weight-to-count) unit
/// conversion for nutrition purposes; a mismatched or missing entry
/// makes that ingredient's contribution entirely unknown, never
/// partially summed. Every contributing field is computed with a
/// single integer truncation, never a chain of `double` operations.
class NutritionAggregator {
  const NutritionAggregator();

  NutritionAggregationOutcome aggregate({
    required List<FlattenedIngredientLine> lines,
    required Map<String, NutritionReferenceEntry>
        referenceEntriesByIngredientId,
  }) {
    final missing = <String>[];
    final contributingConfidences = <NutritionConfidence>[];

    int? energy, protein, carb, fat, satFat, fiber, sugar, salt, sodium;

    for (final line in lines) {
      final entry = referenceEntriesByIngredientId[line.ingredientId];
      if (entry == null ||
          !entry.values.isComplete ||
          entry.referenceUnit != line.quantity.unit) {
        missing.add(line.ingredientId);
        continue;
      }

      contributingConfidences.add(entry.confidence);
      final denominator = 100 * entry.referenceUnit.smallestUnitsPerWhole;
      final numeratorFactor = line.quantity.smallestUnits;

      int scale(int? perHundred) {
        if (perHundred == null) return 0;
        return (perHundred * numeratorFactor) ~/ denominator;
      }

      energy = (energy ?? 0) + scale(entry.values.energyKcal);
      protein = (protein ?? 0) + scale(entry.values.proteinMilligrams);
      carb = (carb ?? 0) + scale(entry.values.carbohydrateMilligrams);
      fat = (fat ?? 0) + scale(entry.values.fatMilligrams);
      satFat = (satFat ?? 0) + scale(entry.values.saturatedFatMilligrams);
      fiber = (fiber ?? 0) + scale(entry.values.fiberMilligrams);
      sugar = (sugar ?? 0) + scale(entry.values.sugarMilligrams);
      salt = (salt ?? 0) + scale(entry.values.saltMilligrams);
      sodium = (sodium ?? 0) + scale(entry.values.sodiumMilligrams);
    }

    NutritionConfidence overallConfidence;
    if (contributingConfidences.isEmpty) {
      overallConfidence = NutritionConfidence.unknown;
    } else {
      overallConfidence =
          contributingConfidences.reduce((a, b) => a.index < b.index ? a : b);
    }

    return NutritionAggregationOutcome(
      totalValues: NutritionValueSet(
        energyKcal: energy,
        proteinMilligrams: protein,
        carbohydrateMilligrams: carb,
        fatMilligrams: fat,
        saturatedFatMilligrams: satFat,
        fiberMilligrams: fiber,
        sugarMilligrams: sugar,
        saltMilligrams: salt,
        sodiumMilligrams: sodium,
      ),
      missingIngredientIds: missing,
      confidence: overallConfidence,
    );
  }
}
