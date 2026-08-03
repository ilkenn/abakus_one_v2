import '../../../shared/models/money.dart';
import '../../inventory/domain/inventory_unit.dart';

/// Strategy contract for resolving one ingredient's unit cost — Phase
/// 7 (`docs/decisions.md` ADR-024). Returns `null` (never a fabricated
/// zero) when nothing usable is on record for the requested [unit].
abstract interface class IngredientCostResolver {
  Future<Money?> resolveUnitCost({
    required String ingredientId,
    required InventoryUnit unit,
  });
}
