import '../../../shared/models/currency.dart';
import '../../../shared/models/money.dart';
import '../../recipes/domain/flattened_ingredient_line.dart';
import 'resolved_ingredient_cost.dart';

class CostAggregationOutcome {
  const CostAggregationOutcome({
    required this.totalCost,
    required this.missingIngredientIds,
  });

  final Money? totalCost;
  final List<String> missingIngredientIds;
}

/// Pure, synchronous aggregation of a flattened ingredient list into a
/// total [Money] cost — Phase 7 (`docs/decisions.md` ADR-024). Mirrors
/// `NutritionAggregator` exactly: no I/O, the caller pre-resolves
/// every [ResolvedIngredientCost] it needs. An ingredient only
/// contributes when a resolved cost exists **and** its [unit] matches
/// the flattened line's `Quantity.unit` exactly — a missing or
/// mismatched cost makes that ingredient's contribution entirely
/// unknown, never partially summed or defaulted to zero.
class CostAggregator {
  const CostAggregator();

  CostAggregationOutcome aggregate({
    required List<FlattenedIngredientLine> lines,
    required Map<String, ResolvedIngredientCost> resolvedCostsByIngredientId,
    required Currency currency,
  }) {
    final missing = <String>[];
    var totalMinorUnits = 0;
    var hasAnyContribution = false;

    for (final line in lines) {
      final resolved = resolvedCostsByIngredientId[line.ingredientId];
      if (resolved == null || resolved.unit != line.quantity.unit) {
        missing.add(line.ingredientId);
        continue;
      }
      final contribution =
          (resolved.unitCost.minorUnits * line.quantity.smallestUnits) ~/
              resolved.unit.smallestUnitsPerWhole;
      totalMinorUnits += contribution;
      hasAnyContribution = true;
    }

    return CostAggregationOutcome(
      totalCost: hasAnyContribution ? Money(totalMinorUnits, currency) : null,
      missingIngredientIds: missing,
    );
  }
}
