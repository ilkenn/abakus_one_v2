import '../../../shared/models/money.dart';
import '../../inventory/domain/inventory_unit.dart';
import '../data/standard_ingredient_cost_repository.dart';
import 'ingredient_cost_resolver.dart';

/// [CostingMethod.standard]: a manually-set [StandardIngredientCost]
/// for the requested [unit] — Phase 7 (`docs/decisions.md` ADR-024).
class StandardCostResolver implements IngredientCostResolver {
  const StandardCostResolver({
    required StandardIngredientCostRepository repository,
  }) : _repository = repository;

  final StandardIngredientCostRepository _repository;

  @override
  Future<Money?> resolveUnitCost({
    required String ingredientId,
    required InventoryUnit unit,
  }) async {
    final cost = await _repository.findByIngredientId(ingredientId);
    if (cost == null || cost.unit != unit) return null;
    return cost.unitCost;
  }
}
