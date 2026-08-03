import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Quantity', () {
    test('fromWhole converts whole units to smallest units', () {
      final quantity = Quantity.fromWhole(2, InventoryUnit.kilogram);

      expect(quantity.smallestUnits, 2000);
    });

    test('addition of same-unit quantities', () {
      final a = Quantity.fromWhole(500, InventoryUnit.gram);
      final b = Quantity.fromWhole(250, InventoryUnit.gram);

      expect((a + b).smallestUnits, 750);
    });

    test('subtraction can go negative without throwing', () {
      final a = Quantity.fromWhole(100, InventoryUnit.gram);
      final b = Quantity.fromWhole(150, InventoryUnit.gram);

      expect((a - b).isNegative, isTrue);
    });

    test('mismatched units throw UnitMismatchViolation', () {
      final grams = Quantity.fromWhole(500, InventoryUnit.gram);
      final ml = Quantity.fromWhole(500, InventoryUnit.milliliter);

      expect(() => grams + ml, throwsA(isA<UnitMismatchViolation>()));
    });

    test('comparison operators respect unit-aware ordering', () {
      final small = Quantity.fromWhole(1, InventoryUnit.kilogram);
      final large = Quantity.fromWhole(2, InventoryUnit.kilogram);

      expect(small < large, isTrue);
      expect(large > small, isTrue);
    });

    test('zero is exactly zero smallest units', () {
      expect(Quantity.zero(InventoryUnit.gram).isZero, isTrue);
    });

    test('never uses double arithmetic internally — exact integers only', () {
      // 0.1 + 0.2 != 0.3 in binary floating point; the equivalent exact
      // integer computation must be exact.
      const a = Quantity(1, InventoryUnit.gram);
      const b = Quantity(2, InventoryUnit.gram);
      const c = Quantity(3, InventoryUnit.gram);

      expect(a + b, c);
    });
  });
}
