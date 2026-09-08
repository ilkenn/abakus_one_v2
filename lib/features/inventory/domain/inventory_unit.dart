/// A unit of measure a [Quantity] can be expressed in — Phase 7
/// (`docs/decisions.md` ADR-024). **Extensible data-instance model**,
/// mirroring `Currency` (`lib/shared/models/currency.dart`): every unit
/// is a value, not an enum branch, so a tenant-defined custom unit ("a
/// bag," "a bucket") is just another instance, never a code change —
/// "custom unit foundation."
class InventoryUnit {
  const InventoryUnit({
    required this.code,
    required this.displayName,
    required this.dimension,
    required this.smallestUnitsPerWhole,
  });

  /// Stable identifier (e.g. `'g'`, `'kg'`, `'ml'`, `'piece'`) — the
  /// only field ever persisted on a [Quantity]/`StockMovement`, so a
  /// unit is always resolved back to the same catalog entry.
  final String code;

  final String displayName;

  /// Units of the same [dimension] can be exactly converted between
  /// each other via a fixed ratio (`kilogram`<->`gram`,
  /// `liter`<->`milliliter`); different dimensions (`weight` vs
  /// `count`) require an ingredient-specific [UnitConversion] — see its
  /// own doc comment.
  final UnitDimension dimension;

  /// How many of this unit's smallest representable increment make one
  /// "whole" of it — mirrors `Currency.minorUnitsPerWhole`. For `gram`
  /// this is `1` (grams are already the smallest tracked increment);
  /// for `kilogram` this is `1000` (expressed internally in grams).
  final int smallestUnitsPerWhole;

  static const gram = InventoryUnit(
    code: 'g',
    displayName: 'gram',
    dimension: UnitDimension.weight,
    smallestUnitsPerWhole: 1,
  );
  static const kilogram = InventoryUnit(
    code: 'kg',
    displayName: 'kilogram',
    dimension: UnitDimension.weight,
    smallestUnitsPerWhole: 1000,
  );
  static const milliliter = InventoryUnit(
    code: 'ml',
    displayName: 'mililitre',
    dimension: UnitDimension.volume,
    smallestUnitsPerWhole: 1,
  );
  static const liter = InventoryUnit(
    code: 'l',
    displayName: 'litre',
    dimension: UnitDimension.volume,
    smallestUnitsPerWhole: 1000,
  );
  static const piece = InventoryUnit(
    code: 'piece',
    displayName: 'adet',
    dimension: UnitDimension.count,
    smallestUnitsPerWhole: 1,
  );
  static const portion = InventoryUnit(
    code: 'portion',
    displayName: 'porsiyon',
    dimension: UnitDimension.count,
    smallestUnitsPerWhole: 1,
  );
  static const package = InventoryUnit(
    code: 'package',
    displayName: 'paket',
    dimension: UnitDimension.count,
    smallestUnitsPerWhole: 1,
  );
  static const tray = InventoryUnit(
    code: 'tray',
    displayName: 'tepsi',
    dimension: UnitDimension.count,
    smallestUnitsPerWhole: 1,
  );
  static const bottle = InventoryUnit(
    code: 'bottle',
    displayName: 'şişe',
    dimension: UnitDimension.count,
    smallestUnitsPerWhole: 1,
  );

  static const List<InventoryUnit> builtIn = [
    gram,
    kilogram,
    milliliter,
    liter,
    piece,
    portion,
    package,
    tray,
    bottle,
  ];

  /// AP-5 Sprint 6 — resolves one of [builtIn] back from its persisted
  /// [code] (e.g. reconstructing a [Quantity] from a Firestore document
  /// that only stores `unitCode` + a smallest-units integer, never the
  /// full unit object). `null` for a tenant-defined custom unit (this
  /// extensibility point's own documented case, above) — never guessed.
  static InventoryUnit? byCode(String code) {
    for (final unit in builtIn) {
      if (unit.code == code) return unit;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is InventoryUnit && other.code == code);

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// What kind of measure an [InventoryUnit] expresses — only units
/// sharing a dimension can be exactly converted via a fixed ratio; a
/// weight<->count conversion always needs an ingredient-specific
/// [UnitConversion] (e.g. "1 package of flour X = 25000 g" is a fact
/// about that specific ingredient, not a universal ratio).
enum UnitDimension { weight, volume, count }
