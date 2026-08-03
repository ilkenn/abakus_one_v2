import '../../../shared/models/money.dart';
import '../../inventory/domain/inventory_unit.dart';
import '../data/purchase_price_repository.dart';
import 'ingredient_cost_resolver.dart';

/// [CostingMethod.latestPurchase]: the most recently recorded
/// [PurchasePrice] for the ingredient, at the requested [unit] —
/// Phase 7 (`docs/decisions.md` ADR-024). A [PurchasePrice] recorded
/// in a different unit is ignored (no cross-unit conversion attempted
/// here, same honest limitation `NutritionAggregator` documents).
class LatestPurchaseCostResolver implements IngredientCostResolver {
  const LatestPurchaseCostResolver(
      {required PurchasePriceRepository repository})
      : _repository = repository;

  final PurchasePriceRepository _repository;

  @override
  Future<Money?> resolveUnitCost({
    required String ingredientId,
    required InventoryUnit unit,
  }) async {
    final prices = await _repository.findByIngredientId(ingredientId);
    final matching = prices.where((p) => p.unit == unit).toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    if (matching.isEmpty) return null;
    return matching.first.pricePerUnit;
  }
}
