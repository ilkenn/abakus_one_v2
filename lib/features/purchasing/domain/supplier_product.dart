import '../../inventory/domain/inventory_unit.dart';

/// One product a [Supplier] sells, mapped to an inventory
/// [Ingredient] — Phase 7 (`docs/decisions.md` ADR-024).
/// [supplierUnit] is deliberately independent of the ingredient's own
/// tracking unit — "supplier-specific units" (a supplier might sell by
/// the case while the kitchen tracks by the kilogram); converting
/// between the two is out of this phase's scope, matching every other
/// documented cross-unit limitation in Phase 7 (`NutritionAggregator`,
/// `CostAggregator`, ...).
class SupplierProduct {
  const SupplierProduct({
    required this.id,
    required this.organizationId,
    required this.supplierId,
    required this.ingredientId,
    required this.supplierProductCode,
    required this.supplierUnit,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String supplierId;
  final String ingredientId;
  final String supplierProductCode;
  final InventoryUnit supplierUnit;
  final DateTime createdAt;
  final int revision;
}
