import '../../../shared/models/money.dart';
import '../../inventory/domain/inventory_unit.dart';

/// The pre-resolved unit cost for one ingredient — Phase 7
/// (`docs/decisions.md` ADR-024). [unitCost] is the price of exactly
/// one whole [unit]. Produced by an `IngredientCostResolver`
/// strategy, consumed by [CostAggregator] (kept separate from the
/// resolver's own async lookup so aggregation itself stays pure and
/// synchronous, mirroring `NutritionAggregator`).
class ResolvedIngredientCost {
  const ResolvedIngredientCost({required this.unitCost, required this.unit});

  final Money unitCost;
  final InventoryUnit unit;
}
