import '../../../shared/models/money.dart';
import '../../inventory/domain/inventory_unit.dart';
import '../data/purchase_price_repository.dart';
import 'ingredient_cost_resolver.dart';

/// [CostingMethod.weightedAverage]: a quantity-weighted average across
/// every recorded [PurchasePrice] for the ingredient at the requested
/// [unit] — Phase 7 (`docs/decisions.md` ADR-024). Weighted by
/// [PurchasePrice.quantityPurchased], not a naive average of prices —
/// a 1000g purchase counts far more than a 10g one. A single integer
/// truncation at the end, never a chain of `double` operations.
class WeightedAverageCostResolver implements IngredientCostResolver {
  const WeightedAverageCostResolver({
    required PurchasePriceRepository repository,
  }) : _repository = repository;

  final PurchasePriceRepository _repository;

  @override
  Future<Money?> resolveUnitCost({
    required String ingredientId,
    required InventoryUnit unit,
  }) async {
    final prices = await _repository.findByIngredientId(ingredientId);
    final matching = prices.where((p) => p.unit == unit).toList();
    if (matching.isEmpty) return null;

    var weightedSum = 0;
    var totalQuantity = 0;
    for (final price in matching) {
      weightedSum +=
          price.pricePerUnit.minorUnits * price.quantityPurchased.smallestUnits;
      totalQuantity += price.quantityPurchased.smallestUnits;
    }
    if (totalQuantity == 0) return null;

    return Money(
        weightedSum ~/ totalQuantity, matching.first.pricePerUnit.currency);
  }
}
