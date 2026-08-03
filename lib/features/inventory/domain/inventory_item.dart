import 'inventory_unit.dart';
import 'negative_stock_policy.dart';
import 'quantity.dart';

/// How an [Ingredient] is actually tracked in stock — Phase 7
/// (`docs/decisions.md` ADR-024). Distinct from `Ingredient` itself:
/// `Ingredient` is food/recipe master data (name, category, base unit);
/// `InventoryItem` is the inventory-management configuration for it
/// (tracking unit, reorder threshold, negative-stock policy) — an
/// ingredient can exist in a recipe before anyone decides to track it
/// in inventory at all.
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.ingredientId,
    required this.organizationId,
    required this.trackingUnit,
    this.reorderThreshold,
    this.negativeStockPolicy = NegativeStockPolicy.forbid,
    this.isActive = true,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String ingredientId;
  final String organizationId;
  final InventoryUnit trackingUnit;

  /// Below this on-hand quantity, the item is due for reorder — read by
  /// the Inventory admin screen only; no automatic purchase order is
  /// ever created from it ("do not implement autonomous purchasing").
  final Quantity? reorderThreshold;

  final NegativeStockPolicy negativeStockPolicy;
  final bool isActive;
  final DateTime createdAt;
  final int revision;

  InventoryItem copyWith({
    Quantity? reorderThreshold,
    bool clearReorderThreshold = false,
    NegativeStockPolicy? negativeStockPolicy,
    bool? isActive,
    required int revision,
  }) {
    return InventoryItem(
      id: id,
      ingredientId: ingredientId,
      organizationId: organizationId,
      trackingUnit: trackingUnit,
      reorderThreshold: clearReorderThreshold
          ? null
          : (reorderThreshold ?? this.reorderThreshold),
      negativeStockPolicy: negativeStockPolicy ?? this.negativeStockPolicy,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
