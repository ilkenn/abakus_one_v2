import 'inventory_unit.dart';
import 'quantity.dart';

/// An ingredient-specific conversion ratio between two [InventoryUnit]s
/// of *different* dimensions — Phase 7 (`docs/decisions.md` ADR-024).
/// Same-dimension conversions (kg<->g, l<->ml) never need this — they
/// convert exactly via `InventoryUnit.smallestUnitsPerWhole` alone (see
/// `Quantity.convertTo`). A cross-dimension fact like "1 package of
/// Flour X = 25000 g" is specific to one [ingredientId], never a
/// universal ratio.
class UnitConversion {
  const UnitConversion({
    required this.id,
    required this.ingredientId,
    required this.fromUnit,
    required this.toUnit,
    required this.fromQuantity,
    required this.toQuantity,
  });

  final String id;
  final String ingredientId;
  final InventoryUnit fromUnit;
  final InventoryUnit toUnit;

  /// E.g. `Quantity.fromWhole(1, InventoryUnit.package)`.
  final Quantity fromQuantity;

  /// E.g. `Quantity.fromWhole(25000, InventoryUnit.gram)` — together
  /// with [fromQuantity], "1 package = 25000 g."
  final Quantity toQuantity;
}
