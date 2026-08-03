import '../../../core/errors/business_rule_violation.dart';
import 'inventory_unit.dart';

/// An exact stock quantity: an integer count of an [InventoryUnit]'s
/// smallest representable increment, never a `double` — Phase 7
/// (`docs/decisions.md` ADR-024). Mirrors `Money`'s exact-integer
/// pattern (`lib/shared/models/money.dart`) precisely, for the same
/// reason: "quantity calculations must avoid binary floating-point
/// errors."
///
/// Two [Quantity] values only combine (`+`, `-`, comparisons) when they
/// share a [unit] — a mismatch throws [CurrencyMismatchViolation]... no,
/// throws [UnitMismatchViolation], mirroring `Money`'s own
/// never-silently-coerce rule.
class Quantity implements Comparable<Quantity> {
  const Quantity(this.smallestUnits, this.unit);

  factory Quantity.fromWhole(int wholeUnits, InventoryUnit unit) {
    return Quantity(wholeUnits * unit.smallestUnitsPerWhole, unit);
  }

  factory Quantity.zero(InventoryUnit unit) => Quantity(0, unit);

  final int smallestUnits;
  final InventoryUnit unit;

  bool get isNegative => smallestUnits < 0;
  bool get isZero => smallestUnits == 0;
  bool get isPositive => smallestUnits > 0;

  Quantity operator +(Quantity other) {
    _requireSameUnit(other);
    return Quantity(smallestUnits + other.smallestUnits, unit);
  }

  Quantity operator -(Quantity other) {
    _requireSameUnit(other);
    return Quantity(smallestUnits - other.smallestUnits, unit);
  }

  Quantity operator -() => Quantity(-smallestUnits, unit);

  Quantity operator *(int factor) => Quantity(smallestUnits * factor, unit);

  @override
  int compareTo(Quantity other) {
    _requireSameUnit(other);
    return smallestUnits.compareTo(other.smallestUnits);
  }

  bool operator <(Quantity other) => compareTo(other) < 0;
  bool operator <=(Quantity other) => compareTo(other) <= 0;
  bool operator >(Quantity other) => compareTo(other) > 0;
  bool operator >=(Quantity other) => compareTo(other) >= 0;

  void _requireSameUnit(Quantity other) {
    if (unit != other.unit) {
      throw UnitMismatchViolation(
        expectedUnitCode: unit.code,
        actualUnitCode: other.unit.code,
      );
    }
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Quantity &&
            other.smallestUnits == smallestUnits &&
            other.unit == unit);
  }

  @override
  int get hashCode => Object.hash(smallestUnits, unit);

  @override
  String toString() {
    final whole = smallestUnits ~/ unit.smallestUnitsPerWhole;
    final remainder = smallestUnits % unit.smallestUnitsPerWhole;
    if (remainder == 0) return '$whole ${unit.code}';
    return '${smallestUnits / unit.smallestUnitsPerWhole} ${unit.code}';
  }
}
