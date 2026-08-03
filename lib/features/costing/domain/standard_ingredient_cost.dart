import '../../../shared/models/money.dart';
import '../../inventory/domain/inventory_unit.dart';

/// A manually-set target/planned unit cost for an ingredient,
/// independent of actual purchase history — Phase 7
/// (`docs/decisions.md` ADR-024). Backs [CostingMethod.standard]. One
/// per ingredient, upserted (see `SetStandardIngredientCost`).
class StandardIngredientCost {
  const StandardIngredientCost({
    required this.id,
    required this.organizationId,
    required this.ingredientId,
    required this.unitCost,
    required this.unit,
    required this.setByStaffId,
    required this.setAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String ingredientId;
  final Money unitCost;
  final InventoryUnit unit;
  final String setByStaffId;
  final DateTime setAt;
  final int revision;
}
