import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InventoryUnit.byCode (AP-5 Sprint 6)', () {
    test('resolves every built-in unit by its code', () {
      for (final unit in InventoryUnit.builtIn) {
        expect(InventoryUnit.byCode(unit.code), unit);
      }
    });

    test('returns null for an unrecognized/custom unit code', () {
      expect(InventoryUnit.byCode('bucket'), isNull);
    });
  });
}
