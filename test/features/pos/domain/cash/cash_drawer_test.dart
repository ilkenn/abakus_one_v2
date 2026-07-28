import 'package:abakus_one_v2/features/pos/domain/cash/cash_drawer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith only changes isActive', () {
    const drawer =
        CashDrawer(id: 'drawer-1', branchId: 'branch-1', name: 'Kasa 1');

    final archived = drawer.copyWith(isActive: false);

    expect(archived.isActive, isFalse);
    expect(archived.id, drawer.id);
    expect(archived.name, drawer.name);
  });

  test('defaults to active', () {
    const drawer =
        CashDrawer(id: 'drawer-1', branchId: 'branch-1', name: 'Kasa 1');
    expect(drawer.isActive, isTrue);
  });
}
